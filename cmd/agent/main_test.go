package main

import (
	"fmt"
	"net"
	"os"
	"testing"

	"github.com/nezhahq/agent/model"
)

func TestLookupIP(t *testing.T) {
	if ci := os.Getenv("CI"); ci != "" { // skip if test on CI
		return
	}

	ip, err := lookupIP("www.google.com")
	fmt.Printf("ip: %v, err: %v\n", ip, err)
	if err != nil {
		t.Errorf("lookupIP failed: %v", err)
	}
	_, err = net.ResolveIPAddr("ip", "www.google.com")
	if err != nil {
		t.Errorf("ResolveIPAddr failed: %v", err)
	}

	ip, err = lookupIP("ipv6.google.com")
	fmt.Printf("ip: %v, err: %v\n", ip, err)
	if err != nil {
		t.Errorf("lookupIP failed: %v", err)
	}
	_, err = net.ResolveIPAddr("ip", "ipv6.google.com")
	if err != nil {
		t.Errorf("ResolveIPAddr failed: %v", err)
	}
}

func TestSelfUpdateRepositoryIsForkOwned(t *testing.T) {
	if got := selfUpdateRepository(updateConfigTuple{}); got != model.DefaultUpdateRepository {
		t.Fatalf("selfUpdateRepository(empty) = %q, want %q", got, model.DefaultUpdateRepository)
	}

	custom := updateConfigTuple{updateRepository: "  laoxiechuzheng/agent-test  "}
	if got := selfUpdateRepository(custom); got != "laoxiechuzheng/agent-test" {
		t.Fatalf("selfUpdateRepository(custom) = %q", got)
	}
}
