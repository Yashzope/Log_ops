-- =============================================================================
-- LogOps — Fluent Bit Lua enrichment
-- Adds a mock geo_country field based on the last octet of the client IP.
-- This is intentionally simple for beginners — real geo-IP uses MaxMind/etc.
-- =============================================================================

-- Map a number 0–9 to a fake country code for demos
local COUNTRY_MAP = {
  [0] = "US",
  [1] = "IN",
  [2] = "GB",
  [3] = "DE",
  [4] = "BR",
  [5] = "JP",
  [6] = "AU",
  [7] = "CA",
  [8] = "FR",
  [9] = "SG",
}

-- Pull the last number from an IPv4 address like "10.0.0.42" -> 42
local function last_octet(ip)
  if ip == nil or ip == "" then
    return 0
  end
  local octet = string.match(ip, "(%d+)$")
  return tonumber(octet) or 0
end

-- Choose a country code from the last octet (modulo 10)
local function mock_country(ip)
  local idx = last_octet(ip) % 10
  return COUNTRY_MAP[idx] or "ZZ"
end

-- Fluent Bit calls this function for every log record
-- tag = input tag, timestamp = event time, record = table of fields
function enrich_record(tag, timestamp, record)
  -- Prefer client_ip from JSON app logs; fall back to nginx remote field
  local ip = record["client_ip"] or record["remote"] or "0.0.0.0"

  -- Add the mock geo enrichment field
  record["geo_country"] = mock_country(ip)

  -- Normalize a few nginx fields into the common schema used downstream
  if record["code"] ~= nil and record["status_code"] == nil then
    record["status_code"] = tonumber(record["code"]) or 0
  end
  if record["path"] ~= nil and record["message"] == nil then
    record["message"] = (record["method"] or "GET") .. " " .. record["path"]
  end
  if record["service"] == nil then
    if tag == "nginx.access" then
      record["service"] = "nginx"
    else
      record["service"] = "unknown"
    end
  end

  -- Return code 1 = modify record in place; keep original timestamp
  return 1, timestamp, record
end
