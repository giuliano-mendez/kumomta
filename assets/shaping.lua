local mod = {}
local kumo = require 'kumo'

-- Helper function that merges the values from `src` into `dest`
local function merge_into(src, dest)
  if src then
    for k, v in pairs(src) do
      dest[k] = v
    end
  end
end

--[[
Usage:

Create a `/opt/kumomta/etc/shaping.json` with contents like:

```json
{
  "gmail.com": {
    // "mx_rollup": false, // if false, is NOT shared with other domains with same mx
    "connection_limit": 3,

    // Entries that are themselves objects are considered to be
    // source configuration. These will take precendence over
    // the more general configuration for the domain/site
    "sources": {
      "source-0": {
        "connection_limit": 5
      }
    }
  }
}
```

---
local shaping = require 'shaping'
kumo.on('get_egress_path_config', shaping:setup_json())
---

]]

function mod:setup_json()
  local function load_shaping_data(filename)
    local data = kumo.json_load(filename)
    local site_to_domains = {}
    local result = {
      by_site = {},
      by_domain = {},
    }
    for domain, config in pairs(data) do
      local entry = {
        sources = {},
        params = {},
      }

      local mx_rollup = config.mx_rollup or true
      config.mx_rollup = nil
      if domain == 'default' then
        mx_rollup = false
      end

      for k, v in pairs(config) do
        if k == 'sources' then
          entry.sources = v
        else
          entry.params[k] = v
        end
      end

      if mx_rollup then
        local site_name = kumo.dns.lookup_mx(domain).site_name
        result.by_site[site_name] = entry

        local site_domains = site_to_domains[site_name] or {}
        table.insert(site_domains, domain)
        site_to_domains[site_name] = site_domains
      else
        result.by_domain[domain] = entry
      end
    end

    local conflicted = {}
    for site, domains in pairs(site_to_domains) do
      if #domains > 1 then
        domains = table.concat(domains, ', ')
        table.insert(conflicted, domains)
        print(
          'Multiple domains rollup to the same site: '
            .. site
            .. ' -> '
            .. domains
        )
      end
    end

    if conflicted then
      -- This will generate a transient failure for every message
      -- until the issue is resolved
      error(
        'multiple conflicting rollup domains '
          .. table.concat(conflicted, ' ')
      )
    end

    -- print(kumo.json_encode(result))
    return result
  end

  local cached_load_data = kumo.memoize(load_shaping_data, {
    name = 'shaping_data',
    ttl = '5 minutes',
    capacity = 10,
  })

  local function get_egress_path_config(domain, egress_source, site_name)
    local data = cached_load_data '/opt/kumomta/etc/shaping.json'

    local by_site = data.by_site[site_name]
    local by_domain = data.by_domain[domain]

    local params = {}

    -- apply basic/default configuration
    merge_into(data.by_domain['default'].params, params)

    -- then site config
    if by_site then
      merge_into(by_site.params, params)
    end
    -- then domain config
    if by_domain then
      merge_into(by_domain.params, params)
    end

    -- then source config for the site
    if by_site then
      merge_into(by_site.sources[egress_source], params)
    end

    -- then source config for the domain
    if by_domain then
      merge_into(by_domain.sources[egress_source], params)
    end

    -- print("going to make egress path", kumo.json_encode(params))

    return kumo.make_egress_path(params)
  end

  return get_egress_path_config
end

return mod
