//! When the hub refreshes its session list and fetches a preview, driven by
//! one repeating tick.
//!
//! Zellij reports a timer with the time that actually passed, not the time
//! asked for, so two timers of different lengths cannot be told apart
//! reliably: on Windows a 0.15 s timer often reports 0.16 s or more. Telling
//! them apart by length once mistook preview timers for the refresh timer,
//! and each mistake started another refresh loop that never ended. With a
//! single tick there is only ever one timer pending, and what each tick does
//! is decided here by counting.

/// What the shell has to do on a tick.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Tick {
    /// Read the session list again.
    pub refresh: bool,
    /// The cursor rested on a row with a screen: fetch its preview.
    pub fetch_preview: bool,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum PreviewWait {
    Idle,
    /// Asked since the last tick: the cursor may still be moving.
    Fresh,
    /// A whole tick passed without the cursor moving.
    Rested,
}

#[derive(Debug)]
pub struct Schedule {
    ticks_per_refresh: u32,
    ticks: u32,
    preview: PreviewWait,
}

impl Schedule {
    /// A schedule that refreshes every `ticks_per_refresh` ticks (at least 1).
    pub fn new(ticks_per_refresh: u32) -> Self {
        Schedule { ticks_per_refresh: ticks_per_refresh.max(1), ticks: 0, preview: PreviewWait::Idle }
    }

    /// The cursor moved onto a row with a screen. Its preview is fetched once
    /// the cursor has stayed there for a full tick, so scrolling through the
    /// list does not fetch every row it passes.
    pub fn want_preview(&mut self) {
        self.preview = PreviewWait::Fresh;
    }

    /// The cursor moved onto a row without a screen.
    pub fn cancel_preview(&mut self) {
        self.preview = PreviewWait::Idle;
    }

    pub fn tick(&mut self) -> Tick {
        self.ticks += 1;
        let refresh = self.ticks >= self.ticks_per_refresh;
        if refresh {
            self.ticks = 0;
        }
        let fetch_preview = self.preview == PreviewWait::Rested;
        self.preview = match self.preview {
            PreviewWait::Fresh => PreviewWait::Rested,
            _ => PreviewWait::Idle,
        };
        Tick { refresh, fetch_preview }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn ticks(schedule: &mut Schedule, count: usize) -> Vec<Tick> {
        (0..count).map(|_| schedule.tick()).collect()
    }

    #[test]
    fn it_refreshes_once_every_n_ticks() {
        let mut schedule = Schedule::new(3);
        let refreshes: Vec<bool> = ticks(&mut schedule, 7).iter().map(|t| t.refresh).collect();
        assert_eq!(refreshes, [false, false, true, false, false, true, false]);
    }

    #[test]
    fn scrolling_never_adds_refreshes() {
        // The bug this replaces: every cursor move could add a refresh loop.
        let mut schedule = Schedule::new(10);
        let mut refreshes = 0;
        for _ in 0..100 {
            schedule.want_preview();
            schedule.want_preview();
            refreshes += usize::from(schedule.tick().refresh);
        }
        assert_eq!(refreshes, 10);
    }

    #[test]
    fn a_preview_is_fetched_once_the_cursor_rests_a_full_tick() {
        let mut schedule = Schedule::new(100);
        schedule.want_preview();
        let fetches: Vec<bool> = ticks(&mut schedule, 4).iter().map(|t| t.fetch_preview).collect();
        assert_eq!(fetches, [false, true, false, false], "once, on the second tick");
    }

    #[test]
    fn moving_again_restarts_the_wait() {
        let mut schedule = Schedule::new(100);
        schedule.want_preview();
        assert!(!schedule.tick().fetch_preview);
        schedule.want_preview(); // moved on before it rested
        assert!(!schedule.tick().fetch_preview);
        assert!(schedule.tick().fetch_preview);
    }

    #[test]
    fn a_cancelled_preview_is_not_fetched() {
        let mut schedule = Schedule::new(100);
        schedule.want_preview();
        schedule.tick();
        schedule.cancel_preview();
        assert!(ticks(&mut schedule, 3).iter().all(|t| !t.fetch_preview));
    }

    #[test]
    fn zero_ticks_per_refresh_means_every_tick() {
        let mut schedule = Schedule::new(0);
        assert!(ticks(&mut schedule, 3).iter().all(|t| t.refresh));
    }
}
