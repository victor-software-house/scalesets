# scalesets

Run self-hosted GitHub Actions runners through GitHub's runner scale sets, from Go or from Swift.

scalesets wraps [actions/scaleset](https://github.com/actions/scaleset), GitHub's Go client for runner scale sets.
It creates and reuses scale sets, takes jobs, issues just-in-time runner configs, adopts runners after a restart and removes lost ones.
The program that uses it decides how many runners fit and starts each one on its own machines.

The Go library sits at the root of this repository.
Other languages call the same code through a C interface in `capi/`, and each binding lives in its own folder, starting with Swift in `swift/`.

The design is in [`docs/design.md`](docs/design.md).
