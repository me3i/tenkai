package main

import (
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"
)

var calendarRegionPattern = regexp.MustCompile(`^[A-Za-z]{2}(?:-[A-Za-z0-9]{1,8})?$`)

type nagerHoliday struct {
	Date             string   `json:"date"`
	Name             string   `json:"name"`
	CountryCode      string   `json:"countryCode"`
	SubdivisionCodes []string `json:"subdivisionCodes"`
	NationalHoliday  bool     `json:"nationalHoliday"`
	HolidayTypes     []string `json:"holidayTypes"`
}

type calendarHoliday struct {
	Date  string   `json:"date"`
	Name  string   `json:"name"`
	Types []string `json:"types"`
}

type calendarFrame struct {
	Status string            `json:"status"`
	Region string            `json:"region"`
	Source string            `json:"source"`
	Error  string            `json:"error,omitempty"`
	Days   []calendarHoliday `json:"days"`
}

type calendarState struct {
	topic    *stateTopic
	cacheDir string
	now      func() time.Time

	mu         sync.Mutex
	generation uint64
}

func resolveCalendarRegion(override string) (string, string, bool) {
	value := strings.TrimSpace(override)
	if value != "" {
		if !calendarRegionPattern.MatchString(value) {
			return "", "", false
		}
		parts := strings.SplitN(strings.ToUpper(value), "-", 2)
		if len(parts) == 2 {
			return parts[0], parts[0] + "-" + parts[1], true
		}
		return parts[0], "", true
	}
	for _, key := range []string{"LC_ALL", "LC_MESSAGES", "LANG"} {
		parts := strings.FieldsFunc(os.Getenv(key), func(r rune) bool { return r == '.' || r == '@' })
		if len(parts) == 0 {
			continue
		}
		locale := parts[0]
		if cut := strings.IndexAny(locale, "_-"); cut >= 0 {
			region := locale[cut+1:]
			if len(region) == 2 && calendarRegionPattern.MatchString(region) {
				return strings.ToUpper(region), "", true
			}
		}
	}
	return "", "", false
}

func filterCalendarHolidays(raw []nagerHoliday, subdivision string) []calendarHoliday {
	out := make([]calendarHoliday, 0, len(raw))
	for _, holiday := range raw {
		include := holiday.NationalHoliday || len(holiday.SubdivisionCodes) == 0
		if !include && subdivision != "" {
			for _, code := range holiday.SubdivisionCodes {
				if strings.EqualFold(code, subdivision) {
					include = true
					break
				}
			}
		}
		if include && holiday.Date != "" && holiday.Name != "" {
			out = append(out, calendarHoliday{Date: holiday.Date, Name: holiday.Name, Types: holiday.HolidayTypes})
		}
	}
	sort.SliceStable(out, func(i, j int) bool {
		if out[i].Date == out[j].Date {
			return out[i].Name < out[j].Name
		}
		return out[i].Date < out[j].Date
	})
	return out
}

func calendarCacheDir() string {
	base := os.Getenv("XDG_CACHE_HOME")
	if base == "" {
		base = filepath.Join(os.Getenv("HOME"), ".cache")
	}
	return filepath.Join(base, "tenkai", "holidays")
}

func (s *calendarState) cachePath(country string, year int) string {
	return filepath.Join(s.cacheDir, country, strconv.Itoa(year)+".json")
}

func decodeHolidayBytes(body []byte) ([]nagerHoliday, error) {
	var holidays []nagerHoliday
	if err := json.Unmarshal(body, &holidays); err != nil {
		return nil, err
	}
	return holidays, nil
}

func (s *calendarState) loadYear(country, subdivision string, year int) ([]calendarHoliday, string, error) {
	path := s.cachePath(country, year)
	cachedBody, cachedErr := os.ReadFile(path)
	cached, decodeErr := decodeHolidayBytes(cachedBody)
	if cachedErr == nil && decodeErr == nil {
		if info, err := os.Stat(path); err == nil && s.now().Sub(info.ModTime()) < 24*time.Hour {
			return filterCalendarHolidays(cached, subdivision), "cache", nil
		}
	}

	// TENKAI: the holiday service fetch is compiled out (no net/http import here).
	// A cached year is still served, even stale; with no cache the year is
	// simply unavailable.
	err := errors.New("tenkai: outbound network disabled")
	if cachedErr == nil && decodeErr == nil {
		return filterCalendarHolidays(cached, subdivision), "stale-cache", err
	}
	return []calendarHoliday{}, "unavailable", err
}

func (d *daemon) startCalendar() {
	s := &calendarState{
		topic:    d.registerTopic("calendar"),
		cacheDir: calendarCacheDir(), now: time.Now,
	}
	s.publish(calendarFrame{Status: "loading", Days: []calendarHoliday{}})
	d.registerCall("calendar.configure", func(raw json.RawMessage) (any, error) {
		var request struct {
			Region string `json:"region"`
			Years  []int  `json:"years"`
		}
		if err := json.Unmarshal(raw, &request); err != nil {
			return nil, err
		}
		s.configure(request.Region, request.Years)
		return map[string]any{"ok": true}, nil
	})
}

func (s *calendarState) configure(region string, years []int) {
	country, subdivision, valid := resolveCalendarRegion(region)
	validationError := ""
	if !valid && strings.TrimSpace(region) != "" {
		validationError = "Invalid holiday region; using system locale"
		country, subdivision, valid = resolveCalendarRegion("")
	}
	if !valid {
		s.publish(calendarFrame{Status: "unavailable", Error: "No supported system locale", Days: []calendarHoliday{}})
		return
	}

	unique := map[int]bool{}
	for _, year := range years {
		if year >= 1970 && year <= 2200 {
			unique[year] = true
		}
	}
	ordered := make([]int, 0, len(unique))
	for year := range unique {
		ordered = append(ordered, year)
	}
	sort.Ints(ordered)

	s.mu.Lock()
	s.generation++
	generation := s.generation
	s.mu.Unlock()
	go func() {
		days := []calendarHoliday{}
		source := "cache"
		lastError := validationError
		for _, year := range ordered {
			loaded, loadedSource, err := s.loadYear(country, subdivision, year)
			days = append(days, loaded...)
			if loadedSource == "network" || source == "cache" {
				source = loadedSource
			}
			if err != nil {
				lastError = err.Error()
			}
		}
		s.mu.Lock()
		current := generation == s.generation
		s.mu.Unlock()
		if !current {
			return
		}
		status := "loaded"
		if len(days) == 0 && lastError != "" {
			status = "unavailable"
		}
		resolved := country
		if subdivision != "" {
			resolved = subdivision
		}
		s.publish(calendarFrame{Status: status, Region: resolved, Source: source, Error: lastError, Days: days})
	}()
}

func (s *calendarState) publish(frame calendarFrame) {
	body, err := json.Marshal(frame)
	if err == nil {
		s.topic.publish(body)
	}
}
