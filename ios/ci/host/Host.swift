// Simulator host for CI screenshots only. The app's @main lives in the DriverLog
// package target; this target just links it so it can run in the simulator.
// On your phone, xtool builds the package directly and doesn't use this.
import DriverLog
