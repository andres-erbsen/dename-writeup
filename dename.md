# Introduction

Public-key cryptography has the potential to provide a general solution for
secure authentication and communication online. However, the difficulty of
public-key distribution has prevented it from becoming
universal[@wpNsaProofEncryption].  Current systems either have single points of
failure or are too cumbersome for humans to use.  Certificate authorities, which
manage public keys for domains, can be completely compromised by a single
breach[@EllisonSchneierPKI][@SchneierVerisignHacked].  Personal PGP keys are
decentralized, but expanding the web of trust is far too laborious and still
suffers from social engineering attacks [@arsTechnicaGGreenwaldPGP], since it
relies on unreadable fingerprints rather than human-meaningful
names[@Johnny2008].  The tradeoff between these systems is expressed in Zooko's
triangle[@ZookosTriangle], which claims that naming systems <!--has this term
been established?--> can provide at most two of three of three properties:
decentralization, human-readability, and security. Aaron Swartz proposed a
system to embed name assignments in a blockchain much like
Bitcoin's[@SwartzSquareZoooko], and Namecoin implements the same idea. Arguably,
it successfully combines all three properties, "squaring" Zooko's triangle.
However, it has a major weakness: an adversary with more hashing power than
honest parties can arbitrarily take over names.  Moreover, even when not
compromised, it requires a massive amount of computation power and requires
each participant to store the entire set of data <!--unless they trust a third
party-->.  In this paper, we propose a new system that uses a distributed set of
untrusted servers and verifiers, only one of which must be honest, to manage
name registrations securely and efficiently. We believe it could make public
keys usable universally.
<!-- todo: cite certificate transparency somewhere -->

# Protocol

## Assumptions

We assume that the user runs a correct copy of the client software and does
not go out of their way to break it -- for example, we are not trying to protect
against the user intentionally revealing the secret key. Endpoint attacks
(e.g., malware or physcal theft) are also assumed not to happen.

We assume that the digital signature scheme (`ed25519`), hash (`sha256`), and
authenticated encryption (`salsa20poly1305`) hold up to their security claims:
unforgeability, collision resistance and `IND-CCA2`. The current implementation
also uses `sha256` with constant-length input for key derivation to provide
fairness under the assumption that it is a perfect entropy extractor. Similarly,
a reliable authenticated transport between servers is required for availability.

## Conventions

All public identities contain a signing key that can be used to transfer names
to other identities. No party ever reveals their secret key. All servers are
expected to save all messages to nonvolatile storage before sending them.


## Main protocol

The dename protocol is run between a fixed set of servers, each of which knows
the addresses <!-- TODO: what kind of addresses? --> and public keys of all the
other servers, its *peers*. Each server stores the entire set of name registrations and
serves it to clients. To introduce a new name registration or update an existing
one, a client contacts a single server of their choice, which becomes the
*introducer* for the request. <!-- do we actually want to use that term? -->
Servers continually accept requests from clients, synchronize the changes, and
agree on updated sets of name registrations.

### Rounds

In order to define a global ordering of requests, time is split into discrete
rounds. Each round goes through the following phases in each server:

- **Accept requests from clients.** The requests are checked for validity given
  the server's current knowledge and stored locally if accepted. The server can
  verify to the client that the request will be processed, but since there could be
  conflicts with requests in the same round on other servers, the server cannot
  guarantee that the request will go through.
- **Commit to the requests.** Once the round is closed for clients, the server
  broadcasts a *commitment* -- a signed hash of its set of requests. However, to
  prevent peers (who might not have committed to their own requests yet)
  from intentionally introducing conflicting requests, the requests themselves
  are not sent yet.
- **Wait for all the commitments and acknowledge them.** For each commitment
  received, the server broadcasts a signed acknowledgement that it saw the
  commitment.
- **Wait for all acknowledgements for all commitments.** The server waits until
  it sees that each peer has acknowledged each other server's requests -- a total of
  $(N-1)^2$ incoming acknowledgements -- and makes sure that the
  acknowledgements match the commitments it saw.
- **Broadcast the requests.** Now that each peer has irreversibly committed to
  its set of requests, the server can send out its own requests.
- **Process the requests.** Once requests have come in from each peer, the
  round's entire set of requests is known, and processed identically on each
  server. To resolve conflicts (names that were assigned to multiple new identities
  in the same round), a cryptographic psuedorandom number generator is seeded based
  on the shared state and used to randomly rank the requests. Then, for each
  name, the winning request is processed and stored.
- **Publish the result.** Once the new set of name registrations has been
  created, the server broadcasts a signed hash.
- **Wait for all publishes.**
- **Start serving the new state to clients.** Once every server has published an
  identical set of name registrations, the state that is served to clients can
  be atomically <!-- atomic on that server --> switched to the new one.

### Enhancements

To spread out the network traffic, each server broadcasts requests it receives
right away, but encrypted with a key that is freshly generated each round.
Then, to give other servers the requests, the servers just broadcast the
round key. In our implementation, a hash of the set of round keys is used to
seed the PRNG in [Step: Process the requests].

## Name-tree representation

To allow for efficient manipulation and verification of the set of name-identity
mappings, we store them in a binary radix tree whose dictionary keys[^1] are
hashes of the names and whose values are hashes of the identities. The tree is
also a Merkle tree: each leaf stores a hash of the (dictionary key, value) pair
it represents, and each internal node stores the hash of its two children's
hashes. Since every piece of data is hashed into the root in a defined manner,
the root hash effectively specifies the entire tree. This allows for several
efficient operations, assuming clients have securely verified the root hashed
with all the servers:

 - **Name lookups**: A client can send a request to a single server with a name.
   The server responds with the associated identity along with a proof that the
name is actually in the tree. The proof consists of the list of hashes stored in
the siblings of all the nodes along the path from the leaf to the root (and an
indication of whether the siblings are to the left or the right of the path) --
the *Merkle hash path*. To verify the proof, the client first hashes together
the (dictionary key, value) pair (i.e. the hashes of the name and the identity).
This hash is then hashed together with the server-provided hash stored in the
sibling of the leaf, resulting in the hash of their parent. This is repeated
recursively, hashing in the rest of the siblings all the way up to the root. If
the resulting root hash matches, the client knows the identity is correct:
Assuming the hash is collision-resistant, the server cannot return any identity
not associated with the name in the original tree, since finding a Merkle hash
path that produces the correct root hash with an incorrect leaf hash is
intractable.
 - **Name absence proofs**: If a requested name is not in the tree, the server
   can prove its absence by returning the name-identity pairs right before and
right after the missing name, as defined by the lexicographical order of the
dictionary keys, along with the associated Merkle hash pathes. The client has to
verify that both hash pathes result give the correct root hash and that there
are indeed no nodes in between: up to their common ancestor, the former only has
left siblings and the latter only has right siblings.

[^1]: We use the term "dictionary keys" to avoid confusion with cryptographic
keys, could be in the identities -- the dictionary values.

## Verifiers, caches


## What we achieve

### Correctness

The state where no names assigned is correct. A state that is reached from a
correct state by a valid transfer or expiration of a name is also correct.  A
name can be transfered on the consensus of the new owner and the previous owner
(if present), represented by a tuple (name, new identity) digitally signed by
both of them. A name expires (is assigned to point to nobody) if it has not been
transferred in some globally fixed number of consequtive rounds. Transferring
names to yourself is allowed.

If a client accepts a name-key mapping as correct, it either is correct or *all*
`dename` servers the client relies on are faulty. As anybody is welcome to run a
verification server, we think the latter is easily avoidable.

### Fairness

We cannot force the servers to treats clients equally, but we can hold them
accountable. Specifically, if a server accepts a name transfer request from a
client, either this request gets processed or the client has proof of the
server's dishonest behavior. If a server does not accept a name transfer
request, the client can try again with another introduction server.

It may happen that multiple servers receive requests to transfer the same name
during the same round. In that case a random request is handled and the others
are ignored. Furthermore, servers cannot see the requests other servers received
before having agreed to process them. This prevents them from contesting
registrations based on the requested name.

### Freshness

Correctness is independent of wall clock time, but usually clients need to
access the latest correct state, not just any one. Clients that have access to
accurate clocks can be assured that either the state they see is one of the two
most recent ones or *all* servers they rely on for freshness are faulty.

### Resilience

Names can be resolved to identities as long as a copy of the mapping is
available. Names can be transferred or expire only when all introduction servers
are functioning properly. Furthermore, clients that require additional verifiers
to have vetted the name mapping also need these servers to be up.


# Further work

## Rate-limiting and anonymity



# Citations https://www.schneier.com/paper-pki-ft.txt schneier on CA-s
https://www.schneier.com/blog/archives/2012/02/verisign_hacked.html schneier on
verisign hack http://www.certificate-transparency.org/what-is-ct certificate
transparency intro that complains about CA accountability
http://arstechnica.com/security/2013/06/guardian-reporter-delayed-e-mailing-nsa-source-because-crypto-is-a-pain/
http://www.washingtonpost.com/blogs/wonkblog/wp/2013/06/14/nsa-proof-encryption-exists-why-doesnt-anyone-use-it/
http://www.cs.berkeley.edu/~tygar/papers/Why_Johnny_Cant_Encrypt/USENIX.pdf
PGP5 http://www.net.t-labs.tu-berlin.de/teaching/ss08/IS_seminar/PDF/C.1.pdf
PGP9 http://groups.csail.mit.edu/uid/projects/secure-email/soups05.pdf key
continuity paper; includes numbers about PGP usability
http://letstalkbitcoin.com/is-bitcoin-overpaying-for-false-security/ blog post
about bitcoin security-powerusage tradeoff


# Motivation

## Public keys are the best representation of identity

- Identity is well-defined: the public key points to the one who knows the
  corresponding secret key
- One can prove that they know the secret key.
  - if only the prover is online, use signatures
  - if only the verifier is online, use decryption
-

## Public keys are inconvenient to manage

- Public key distribution is hard
- The need to "verify the fingerprint" is not intuitive; lack of usability leads
  to lack of use and thus insecurity
- wide social engineering attack surface

## Name-Identity mapping would help

- The concept of "usernames" is already widespread
- User interfaces would not need to change to allow for better security

# Prior work

## Zooko's Triangle

It has been conjectured that no system will be able to reference people in a way
that is human-meaningful, secure, and without single points of failure.

## Centralized systems

### Certificate Authorities

- A name can be associated with multiple keys, even without the "owner" knowing.
  Certificate Transparency fixes this.
- Failure of *any* CA will result in arbitrary changes. Both issues are already
  being abused by governments.

## Convergence;

- Only for publicly accessible servers, no obvious extension to users
- Downtime would break everything

### DNS TXT records

- No accountability -- can return whatever they want in response to queries
- Centralized; single point of failure. This is already being abused by
  governments.

## Swartz's, Namecoin

 - Requests are ordered by the one who hashes the fastest and verified by all
   clients.

 Problems:

 - Client-side verification is expensive, no defined protocol for thin clients
 - 51% attack
 - No conventional accountability
 - Operating costs and questionable incentive schemes



