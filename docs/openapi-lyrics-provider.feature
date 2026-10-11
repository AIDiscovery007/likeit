Feature: Optional official NetEase lyric provider
  The coordinating reviewer freezes this additive contract before implementation.
  Existing matching, tests, and user music state remain unchanged.

  Scenario: No application configuration yet
    Given the private configuration file does not exist
    When the immersive desktop requests lyrics
    Then the existing public search, detail verification, and lyric path is used
    And no authenticated OpenAPI request occurs

  Scenario: Configure later without shipping credentials
    Given the user has their own application permission
    Then the product documents an external per-user JSON configuration and PKCS8 PEM path
    And missing, unsafe, malformed, oversized, or incomplete explicit configuration produces a safe error
    And private key, token, device values, and raw server messages never appear in logs or user errors

  Scenario: Resolve the current recording without guessing IDs
    Given the unchanged public resolver has uniquely matched full metadata and verified detail
    When the signed official manifest discovers search song
    Then the search request uses only declared supported parameters and validated official paths
    And only an explicit originalId exactly equal to the verified numeric ID may supply a 32-hex songId or encryptedId
    And conflicting mappings fail, while identical pairs may be deduplicated
    And UUIDs, numeric-to-hex conversions, missing originalId, and title-only guesses are rejected
    And a missing first-page mapping says it was not confirmed, not that the song does not exist

  Scenario: Show synchronized original lyrics
    Given a verified official ID mapping
    When the supplied word endpoint returns code 200 and synchronized data.lrc
    Then the existing LRC timeline renders the original text
    And the source remains labeled as matched by song information
    And no word timing or translated word timing is invented

  Scenario: No word lyrics still permits ordinary lyrics
    Given code 200 with data null or no synchronized original lrc
    When the manifest declares a supported song lyric command
    Then request ordinary lyrics once with the same verified encrypted ID
    And use only data.lyric or data.lrc.lyric original LRC
    And empty ordinary lyrics produces an explicit no-synchronized-lyrics result

  Scenario: Errors are not no-lyrics successes
    Given an API error, malformed payload, HTTP failure, timeout, unsupported manifest, or failed mapping
    Then no previous track lyrics or raw error body is displayed
    And no guessed endpoint, login, anonymous token, or public fallback is attempted
    And the failure is bounded and distinguishable from a legitimate empty lyric result

  Scenario: Constrain signed requests
    Then all requests use HTTPS openapi.music.163.com and validated /openapi/ paths
    And cookies, URL credential storage, persistent caches, and redirects are disabled
    And each request is bounded to five seconds and one MiB
    And the complete provider request is bounded to fifteen seconds
    And the native public pipeline retains its existing fifteen-second deadline
    And RSA signatures cover the exact raw string parameters eventually transmitted

  Scenario: Cancel, switch, and exit
    Given an official lyric request is pending
    When another track begins or the desktop cancels or exits
    Then the old operation is cancelled
    And its late callback cannot publish or launch another request
    And the replacement track can independently complete
