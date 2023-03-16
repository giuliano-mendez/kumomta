# `kumo.dkim.ed25519_signer {PARAMS}`

Create a DKIM signer that uses ED25519 keys.

The key data must be PKCS8 DER encoded data.

This function will attempt to load V2 data first,
which must contain the matching public and private key pair.

If the data cannot be loaded as V2, then it will fall back
to try to load V1 data, which contains just the private key.

```lua
-- Called once the body has been received.
-- For multi-recipient mail, this is called for each recipient.
kumo.on('smtp_server_message_received', function(msg)
  local signer = kumo.dkim.ed25519_signer {
    domain = msg:from_header().domain,
    selector = 'default',
    headers = { 'From', 'To', 'Subject' },
    key = 'example-private-dkim-key.der',
  }
  msg:dkim_sign(signer)
end)
```

`PARAMS` is a lua table that can have the following keys:

## domain

Required. The domain for which the mail is being signed.

## selector

Required. The selector used for signing

## headers

Required. The list of headers which should be signed.

## atps

Optional string. Allows setting the [Authorized Third-Party
signature](https://www.rfc-editor.org/rfc/rfc6541.html).

## atpsh

Optional string. Set the [Authorized Third-Party
Signature](https://www.rfc-editor.org/rfc/rfc6541.html) hashing algorithm.

## agent_user_identifier

Optional string. Sets the [Agent of User Identifier
(AUID)](https://www.rfc-editor.org/rfc/rfc6376.html#section-2.6) to use for
signing.

## expiration

Optional number. Sets the number of seconds from now to use for
the signature expiration.

## body_length

Optional boolean. If `true`, the body length will be included
in the signature.

## reporting

Optional boolean. If `true`, the signature will be marked as
requesting reports from the receiver/verifier.

## header_canonicalization

Specify the canonicalization method to be used when hashing message
headers.  Can be one of:

* `"Relaxed"` - this is the default
* `"Simple"`

## source

Required. Specify the signing key. Currently accepts two different forms:

* *string* - path to the file from which the signing key will be loaded.
* *object* - load the key from a key management store

The key must be either RSA PEM or a PKCS8 PEM encoded.

```lua
local file_signer = kumo.dkim.rsa_sha256_signer {
  domain = msg:from_header().domain,
  selector = 'default',
  headers = { 'From', 'To', 'Subject' },
  key = '/path/to/example-private-dkim-key.pem',
}
```

using [HashiCorp Vault](https://www.hashicorp.com/products/vault):

```lua
local file_signer = kumo.dkim.rsa_sha256_signer {
  domain = msg:from_header().domain,
  selector = 'default',
  headers = { 'From', 'To', 'Subject' },
  key = {
    vault_mount = 'secret',
    vault_path = 'dkim/' .. msg:from_header().domain,

    -- Specify how to reach the vault; if you omit these,
    -- values will be read from $VAULT_ADDR and $VAULT_TOKEN

    -- vault_address = "http://127.0.0.1:8200"
    -- vault_token = "hvs.TOKENTOKENTOKEN"
  },
}
```

The key must be stored as `key` under the `path` specified.
For example, you might populate it like this:

```
$ vault kv put -mount=secret dkim/example.org key=@example-private-dkim-key.pem
```

## ttl

Optional number. Specifies the time-to-live (TTL) in KumoMTA's DKIM signer
cache.  The default is `300` seconds.

Each call to this function with the same parameters is cached for up to the
specified TTL in order to avoid the overhead of repeatedly load the key from
disk.