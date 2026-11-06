package cli

import (
	"errors"
	"strings"

	"github.com/pelletier/go-toml/v2"
	"github.com/zricethezav/gitleaks/v8/config"
)

func scannerConfiguration() ([]byte, error) {
	var settings map[string]any
	if toml.Unmarshal([]byte(config.DefaultConfig), &settings) != nil {
		return nil, errors.New("cannot decode pinned detector configuration")
	}
	// Import the pinned maintained rules, not their source-tree path exemptions.
	// Extending useDefault would silently reintroduce exclusions for report
	// scripts named bootstrap.js, node_modules, SVGs, and similar evidence.
	delete(settings, "extend")
	stripPathAllowlists(settings)
	rules, ok := settings["rules"].([]any)
	if !ok || len(rules) == 0 {
		return nil, errors.New("pinned detector configuration has no rules")
	}
	foundJiraRule := false
	for _, entry := range rules {
		rule, ok := entry.(map[string]any)
		if !ok {
			return nil, errors.New("invalid pinned detector rule")
		}
		stripPathAllowlists(rule)
		if rule["id"] == "generic-api-key" {
			foundJiraRule = true
			lists, _ := rule["allowlists"].([]any)
			rule["allowlists"] = append(lists, map[string]any{"description": "Exact Jira metadata assignments are identifiers, not API keys", "regexTarget": "line", "regexes": []string{`(?i)^\s*(?:-\s*)?(?:key|jira_key):\s*[A-Z][A-Z0-9_]*-[0-9]+\s*$`}})
		}
	}
	if !foundJiraRule {
		return nil, errors.New("pinned detector configuration is missing the Jira false-positive rule")
	}
	lists, _ := settings["allowlists"].([]any)
	settings["allowlists"] = append(lists, map[string]any{"description": "Git internals and local tool output only", "paths": []string{`^\.git(/|$)`, `^\.work/`, `^bin/`}})
	return toml.Marshal(settings)
}

func stripPathAllowlists(settings map[string]any) {
	if single, ok := settings["allowlist"].(map[string]any); ok {
		// Normalize the deprecated singular form before adding modern lists.
		delete(settings, "allowlist")
		if keepAllowlistWithoutPaths(single) {
			lists, _ := settings["allowlists"].([]any)
			settings["allowlists"] = append(lists, single)
		}
	}
	if lists, ok := settings["allowlists"].([]any); ok {
		kept := make([]any, 0, len(lists))
		for _, entry := range lists {
			if list, ok := entry.(map[string]any); ok && keepAllowlistWithoutPaths(list) {
				kept = append(kept, list)
			}
		}
		settings["allowlists"] = kept
	}
}

func keepAllowlistWithoutPaths(list map[string]any) bool {
	if _, hasPaths := list["paths"]; !hasPaths {
		return true
	}
	if condition, _ := list["condition"].(string); strings.EqualFold(condition, "AND") {
		return false
	}
	delete(list, "paths")
	for _, key := range []string{"regexes", "stopwords", "commits"} {
		if values, ok := list[key].([]any); ok && len(values) > 0 {
			return true
		}
	}
	return false
}
