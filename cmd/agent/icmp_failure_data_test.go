package main

import "testing"

func TestFormatICMPFailureDataIncludesResolvedTargetIP(t *testing.T) {
	if got := formatICMPFailureData("192.0.2.20", "packets recv 0"); got != "icmp ping target=192.0.2.20: packets recv 0" {
		t.Fatalf("formatICMPFailureData() = %q", got)
	}
}
