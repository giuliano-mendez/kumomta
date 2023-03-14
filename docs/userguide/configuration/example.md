# An Example Configuration

A default policy file is not published with KumoMTA to prevent the average installation from having an excess of commented-out boilerplate from filling production configurations.

The following serves as an example of a complete base policy for a functional installation that addresses common use cases for a typical installation. This is not intended as a copy/paste policy file, but as an example to direct new users in developing their server policy file.

```lua
local kumo = require 'kumo'

-- Called on startup to initialize the system
kumo.on('init', function()
  -- Define a listener.
  -- Can be used multiple times with different parameters to
  -- define multiple listeners!
  kumo.start_esmtp_listener {
    listen = '0.0.0.0:2025',
    -- Override the hostname reported in the banner and other
    -- SMTP responses:
    -- hostname="mail.example.com",

    -- override the default set of relay hosts
    relay_hosts = { '127.0.0.1', '192.168.1.0/24' },

    -- Customize the banner.
    -- The configured hostname will be automatically
    -- prepended to this text.
    banner = 'Welcome to KumoMTA!',

    -- Unsafe! When set to true, don't save to spool
    -- at reception time.
    -- Saves IO but may cause you to lose messages
    -- if something happens to this server before
    -- the message is spooled.
    deferred_spool = false,

    -- max_recipients_per_message = 1024
    -- max_messages_per_connection = 10000,
  }

  kumo.configure_local_logs {
    log_dir = '/var/tmp/kumo-logs',
  }

  kumo.start_http_listener {
    listen = '0.0.0.0:8000',
    -- allowed to access any http endpoint without additional auth
    trusted_hosts = { '127.0.0.1', '::1' },
  }
  kumo.start_http_listener {
    use_tls = true,
    listen = '0.0.0.0:8001',
    -- allowed to access any http endpoint without additional auth
    trusted_hosts = { '127.0.0.1', '::1' },
  }

  -- Define the default "data" spool location; this is where
  -- message bodies will be stored
  --
  -- 'flush' can be set to true to cause fdatasync to be
  -- triggered after each store to the spool.
  -- The increased durability comes at the cost of throughput.
  --
  -- kind can be 'LocalDisk' (currently the default) or 'RocksDB'.
  --
  -- LocalDisk stores one file per message in a filesystem hierarchy.
  -- RocksDB is a key-value datastore.
  --
  -- RocksDB has >4x the throughput of LocalDisk, and enabling
  -- flush has a marginal (<10%) impact in early testing.
  kumo.define_spool {
    name = 'data',
    path = '/var/tmp/kumo-spool/data',
    flush = false,
    kind = 'RocksDB',
  }

  -- Define the default "meta" spool location; this is where
  -- message envelope and metadata will be stored
  kumo.define_spool {
    name = 'meta',
    path = '/var/tmp/kumo-spool/meta',
    flush = false,
    kind = 'RocksDB',
  }

  -- Use shared throttles rather than in-process throttles
  -- kumo.configure_redis_throttles { node = 'redis://127.0.0.1/' }

  -- Create some example sources
  local entries = {}
  for i = 1, 10 do
    local source_name = 'source' .. tostring(i)
    kumo.define_egress_source {
      name = source_name,
    }
    table.insert(entries, { name = source_name, weight = i * 10 })
  end
  kumo.define_egress_pool {
    name = 'pool0',
    entries = entries,
  }
end)

-- Called to validate the helo and/or ehlo domain
kumo.on('smtp_server_ehlo', function(domain)
  -- print('ehlo domain is', domain)
  -- Use kumo.reject to return an error to the EHLO command
  -- kumo.reject(420, 'wooooo!')
end)

-- Called to validate the sender
kumo.on('smtp_server_mail_from', function(sender)
  -- print('sender', tostring(sender))
  -- kumo.reject(420, 'wooooo!')
end)

-- Called to validate a recipient
kumo.on('smtp_server_rcpt_to', function(rcpt)
  -- print('rcpt', tostring(rcpt))
end)

-- Called once the body has been received.
-- For multi-recipient mail, this is called for each recipient.
kumo.on('smtp_server_message_received', function(msg)
  -- print('id', msg:id(), 'sender', tostring(msg:sender()))
  -- print(msg:get_meta 'authn_id')

  -- Import scheduling information from X-Schedule and
  -- then remove that header from the message
  msg:import_scheduling_header('X-Schedule', true)

  local signer = kumo.dkim.rsa_sha256_signer {
    domain = msg:sender().domain,
    selector = 'default',
    headers = { 'From', 'To', 'Subject' },
    -- Using a file:
    key = 'example-private-dkim-key.pem',
    -- Using HashiCorp Vault:
    --[[
    key = {
      vault_mount = "secret",
      vault_path = "dkim/" .. msg:sender().domain
    }
    ]]
  }
  msg:dkim_sign(signer)

  -- set/get metadata fields
  -- msg:set_meta('X-TestMSG', 'true')
  -- print('meta X-TestMSG is', msg:get_meta 'X-TestMSG')
end)

-- Not the final form of this API, but this is currently how
-- we retrieve configuration used when making outbound
-- connections
kumo.on('get_egress_path_config', function(domain, site_name)
  return kumo.make_egress_path {
    enable_tls = 'OpportunisticInsecure',
    -- max_message_rate = '5/min',
    idle_timeout = '5s',
    max_connections = 1024,
    -- max_deliveries_per_connection = 5,

    -- hosts that we should consider to be poison because
    -- they are a mail loop. The default for this is
    -- { "127.0.0.0/8", "::1" }, but it is emptied out
    -- in this config because we're using this to test
    -- with fake domains that explicitly return loopback
    -- addresses!
    prohibited_hosts = {},
  }
end)

-- Not the final form of this API, but this is currently how
-- we retrieve configuration used for managing a queue.
kumo.on('get_queue_config', function(domain, tenant, campaign)
  if domain == 'maildir.example.com' then
    -- Store this domain into a maildir, rather than attempting
    -- to deliver via SMTP
    return kumo.make_queue_config {
      protocol = {
        maildir_path = '/var/tmp/kumo-maildir',
      },
    }
  end

  return kumo.make_queue_config {
    -- Age out messages after being in the queue for 2 minutes
    -- max_age = "2 minutes"
    -- retry_interval = "2 seconds",
    -- max_retry_interval = "8 seconds",
    egress_pool = 'pool0',
  }
end)

-- A really simple inline auth "database" for very basic HTTP authentication
function simple_auth_check(user, password)
  local password_database = {
    ['scott'] = 'tiger',
  }
  if password == '' then
    return false
  end
  return password_database[user] == password
end

-- Consult a hypothetical sqlite database that has an auth table
-- with user and pass fields
function sqlite_auth_check(user, password)
  local sqlite = require 'sqlite'
  local db = sqlite.open '/path/to/auth.db'
  local result = db:execute(
    'select user from auth where user=? and pass=?',
    user,
    password
  )
  return #result == 1
end

-- Use this to lookup and confirm a user/password credential
-- used with the http endpoint
kumo.on('http_server_validate_auth_basic', function(user, password)
  return simple_auth_check(user, password)

  -- or use sqlite
  -- return sqlite_auth_check(user, password)
end)

-- Use this to lookup and confirm a user/password credential
-- when the client attempts SMTP AUTH PLAIN
kumo.on('smtp_server_auth_plain', function(authz, authc, password)
  return simple_auth_check(authc, password)
  -- or use sqlite
  -- return sqlite_auth_check(authc, password)
end)
```