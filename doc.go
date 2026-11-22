// Package scalesets runs self-hosted GitHub Actions runners through
// GitHub's runner scale sets.
//
// It signs in as a GitHub App, keeps a runner group and its scale sets, and
// listens for jobs. It also issues the config each new runner needs. The
// program that uses it decides how many runners fit, and starts each one.
package scalesets
