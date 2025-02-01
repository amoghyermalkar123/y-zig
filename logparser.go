package parser

import (
	"bufio"
	"encoding/json"
	"fmt"
	"os"
	"time"
)

// ReplaySession represents a complete replay session
type ReplaySession struct {
	ID        string     `json:"id"`
	LogFile   string     `json:"log_file"`
	CreatedAt time.Time  `json:"created_at"`
	Events    []EventLog `json:"events"`
	// Metadata for the replay session
	CurrentIndex int   `json:"current_index"`
	StartTime    int64 `json:"start_time"`
	EndTime      int64 `json:"end_time"`
}

// ReplayState represents the current state of replay playback
type ReplayState struct {
	SessionID    string  `json:"session_id"`
	CurrentIndex int     `json:"current_index"`
	IsPlaying    bool    `json:"is_playing"`
	PlaybackRate float64 `json:"playback_rate"`
	// Timestamps for relative time calculations
	CurrentTimestamp int64 `json:"current_timestamp"`
	StartTimestamp   int64 `json:"start_timestamp"`
}

// ReplayCommand represents commands for controlling replay
type ReplayCommand struct {
	Command string `json:"command"`         // play, pause, step_forward, step_back, seek
	Value   string `json:"value,omitempty"` // Used for seek position or playback rate
}

// NewReplaySession creates a new replay session from parsed logs
func NewReplaySession(logFile string, events []EventLog) *ReplaySession {
	var startTime, endTime int64
	if len(events) > 0 {
		startTime = events[0].Data.Timestamp
		endTime = events[len(events)-1].Data.Timestamp
	}

	return &ReplaySession{
		ID:        GenerateID(),
		LogFile:   logFile,
		CreatedAt: time.Now(),
		Events:    events,
		StartTime: startTime,
		EndTime:   endTime,
	}
}

// GenerateID creates a unique session identifier
func GenerateID() string {
	return time.Now().Format("20060102-150405-") + RandomString(6)
}

// RandomString generates a random string of specified length
func RandomString(length int) string {
	// Implementation using crypto/rand would go here
	// For brevity, returning a placeholder
	return "random"
}

// EventsByTimeRange returns events within the specified time range
func (rs *ReplaySession) EventsByTimeRange(start, end int64) []EventLog {
	var filtered []EventLog
	for _, event := range rs.Events {
		if event.Data.Timestamp >= start && event.Data.Timestamp <= end {
			filtered = append(filtered, event)
		}
	}
	return filtered
}

// GetEvent returns the event at the specified index
func (rs *ReplaySession) GetEvent(index int) *EventLog {
	if index < 0 || index >= len(rs.Events) {
		return nil
	}
	return &rs.Events[index]
}

// Duration returns the total duration of the replay session in milliseconds
func (rs *ReplaySession) Duration() int64 {
	return rs.EndTime - rs.StartTime
}

// BlockID represents the common block identifier structure
type BlockID struct {
	Clock  int `json:"clock"`
	Client int `json:"client"`
}

// Origin represents the common origin structure
type Origin struct {
	Clock  int `json:"clock"`
	Client int `json:"client"`
}

// EventLog represents the primary log structure with flexible event data
type EventLog struct {
	Data struct {
		EventType string  `json:"event_type,omitempty"`
		Phase     string  `json:"phase,omitempty"`
		BlockID   BlockID `json:"block_id,omitempty"`
		Content   string  `json:"content,omitempty"`

		// Origins and positions
		LeftOrigin  *Origin `json:"left_origin,omitempty"`
		RightOrigin *Origin `json:"right_origin,omitempty"`
		Left        *Origin `json:"left,omitempty"`
		Right       *Origin `json:"right,omitempty"`

		// Additional fields
		Timestamp int64  `json:"timestamp"`
		Msg       string `json:"msg,omitempty"`
		Details   string `json:"details,omitempty"`
	} `json:"data"`
}

func parseLogFile(filename string) ([]EventLog, error) {
	file, err := os.Open(filename)
	if err != nil {
		return nil, fmt.Errorf("error opening file: %v", err)
	}
	defer file.Close()

	var logs []EventLog
	scanner := bufio.NewScanner(file)

	for scanner.Scan() {
		line := scanner.Text()
		if line == "" {
			continue
		}

		var log EventLog
		if err := json.Unmarshal([]byte(line), &log); err != nil {
			return nil, fmt.Errorf("error parsing JSON line: %v\nLine: %s", err, line)
		}

		logs = append(logs, log)
	}

	if err := scanner.Err(); err != nil {
		return nil, fmt.Errorf("error reading file: %v", err)
	}

	return logs, nil
}

func Parse() ([]EventLog, error) {
	logs, err := parseLogFile("/home/amogh/projects/y-zig/test.log")
	if err != nil {
		fmt.Printf("Error parsing log file: %v\n", err)
		return nil, err
	}
	return logs, nil
}
