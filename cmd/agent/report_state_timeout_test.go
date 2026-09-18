package main

import (
	"context"
	"testing"
	"testing/synctest"
	"time"

	"github.com/nezhahq/agent/model"
)

func TestReportStateRecvTimeoutCancelsHalfOpenStream(t *testing.T) {
	synctest.Test(t, func(t *testing.T) {
		originalInitialized := initialized
		originalDependencies := reportMonitorDependencies
		t.Cleanup(func() {
			initialized = originalInitialized
			reportMonitorDependencies = originalDependencies
		})

		initialized = true
		reportMonitorDependencies.trackNetworkSpeed = func(*model.AgentConfig) {}
		reportMonitorDependencies.getState = func(*model.AgentConfig, bool, bool) *model.HostState {
			return &model.HostState{}
		}
		reportSession := newReportStateSession(context.Background())
		stream := newReportSystemStateStreamFixture(reportSession.streamContext, streamCallAllowance{
			send: 1,
			recv: 1,
		})
		reportSession.bind(stream)

		done := make(chan error, 1)
		go func() {
			_, err := reportState(reportSession, reportSchedule{}, reportConfigTuple{})
			done <- err
		}()

		<-stream.writeEntered
		stream.releaseWrite(streamWriteSend, nil)
		<-stream.recvEntered

		time.Sleep(11 * time.Second)
		synctest.Wait()

		select {
		case err := <-done:
			if err == nil {
				t.Fatal("ReportSystemState half-open Recv returned nil error")
			}
			if context.Cause(reportSession.streamContext) == nil {
				t.Fatal("ReportSystemState half-open Recv did not cancel the stream")
			}
		default:
			t.Fatal("ReportSystemState half-open Recv remained blocked without a deadline")
		}
	})
}
