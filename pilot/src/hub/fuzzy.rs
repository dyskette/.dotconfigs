//! Fuzzy matching for the hub's filter: every whitespace-separated term of
//! the query must appear in the text as a subsequence, case-insensitively.
//! The score favours matches at the start, after a separator (`/ \ - _ .` or
//! a space), at a camelCase hump and in consecutive runs, so `cer` ranks
//! `acme/cerberus` above `docs-agent-generator`.

const MATCH: i32 = 16;
const CONSECUTIVE: i32 = 12;
const START: i32 = 14;
const BOUNDARY: i32 = 10;
const CAMEL: i32 = 6;
/// Cost of each character skipped between two matched ones.
const GAP: i32 = 1;
/// Cap on the cost of the characters before the first match.
const MAX_LEAD: i32 = 6;

/// Score `text` against `query`; `None` when a term does not match. An empty
/// query matches everything with score 0.
pub fn score(query: &str, text: &str) -> Option<i32> {
    let chars: Vec<char> = text.chars().collect();
    let lower: Vec<char> = chars.iter().flat_map(|c| c.to_lowercase()).collect();
    // to_lowercase can change the length for a few characters; such text is
    // matched on the lowered form alone.
    let chars = if lower.len() == chars.len() { chars } else { lower.clone() };

    let mut total = 0;
    for term in query.split_whitespace() {
        let term: Vec<char> = term.chars().flat_map(|c| c.to_lowercase()).collect();
        total += score_term(&term, &chars, &lower)?;
    }
    // Among equal matches the shorter text is the closer one.
    Some(total - (chars.len() as i32) / 8)
}

/// Bonus for matching the character at `index`, from what precedes it.
fn position_bonus(text: &[char], index: usize) -> i32 {
    if index == 0 {
        return START;
    }
    let previous = text[index - 1];
    if matches!(previous, '/' | '\\' | '-' | '_' | '.' | ' ') {
        BOUNDARY
    } else if previous.is_lowercase() && text[index].is_uppercase() {
        CAMEL
    } else {
        0
    }
}

/// Best score of `term` as a subsequence of `text` (dynamic programming over
/// the position each term character is matched at).
fn score_term(term: &[char], text: &[char], lower: &[char]) -> Option<i32> {
    if term.is_empty() {
        return Some(0);
    }
    let n = text.len();
    // previous[j]: best score with the last matched term character at j.
    let mut previous: Vec<Option<i32>> = vec![None; n];

    for (i, wanted) in term.iter().enumerate() {
        let mut current: Vec<Option<i32>> = vec![None; n];
        // Best previous[k] for k <= j - 2, less the gap between k and j.
        let mut across_gap: Option<i32> = None;
        for j in 0..n {
            if j >= 2 {
                across_gap = [across_gap.map(|s| s - GAP), previous[j - 2].map(|s| s - GAP)]
                    .into_iter()
                    .flatten()
                    .max();
            }
            if lower[j] != *wanted {
                continue;
            }
            let bonus = MATCH + position_bonus(text, j);
            current[j] = if i == 0 {
                Some(bonus - (j as i32).min(MAX_LEAD))
            } else {
                let adjacent = if j >= 1 { previous[j - 1].map(|s| s + CONSECUTIVE) } else { None };
                [adjacent, across_gap].into_iter().flatten().max().map(|s| s + bonus)
            };
        }
        previous = current;
    }
    previous.into_iter().flatten().max()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn requires_every_character_in_order() {
        assert!(score("cer", "acme/cerberus").is_some());
        assert!(score("crb", "cerberus").is_some());
        assert!(score("xyz", "cerberus").is_none());
        assert!(score("orbe", "cerberus").is_none());
    }

    #[test]
    fn is_case_insensitive() {
        assert!(score("api", "XY1234-API_AGENT").is_some());
        assert!(score("API", "tools/api").is_some());
    }

    #[test]
    fn empty_query_matches_everything() {
        assert_eq!(score("", "anything"), Some(0 - 1));
        assert!(score("   ", "anything").is_some());
    }

    #[test]
    fn prefers_starts_and_boundaries_over_scattered_letters() {
        let boundary = score("cer", "acme/cerberus").unwrap();
        let scattered = score("cer", "docs-agent-generator").unwrap();
        assert!(boundary > scattered, "{boundary} should beat {scattered}");

        let start = score("sen", "sentinel").unwrap();
        let middle = score("sen", "misc/absent").unwrap();
        assert!(start > middle, "{start} should beat {middle}");
    }

    #[test]
    fn prefers_consecutive_runs() {
        let run = score("time", "globex/globex-time").unwrap();
        let spread = score("time", "acme/tax-invoice-ms-engine").unwrap();
        assert!(run > spread, "{run} should beat {spread}");
    }

    #[test]
    fn all_terms_must_match_in_any_order() {
        assert!(score("acm cer", "acme/cerberus").is_some());
        assert!(score("cer acm", "acme/cerberus").is_some());
        assert!(score("acm zzz", "acme/cerberus").is_none());
    }

    #[test]
    fn prefers_the_shorter_of_two_equal_matches() {
        let short = score("api", "api").unwrap();
        let long = score("api", "api-with-a-much-longer-name-after-it").unwrap();
        assert!(short > long);
    }
}
