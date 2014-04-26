There is nothing sophisticated in this work. What we are proposing is a way to
use techniques that are well-understood and often dismissed as trivial to build
a public key distribution mechanism we consider suitable for universal adoption.

# Abstract

Many applications rely on some form of directory service for connecting
human-meaningful user identifiers (names) with application data associated with
that user. When trying to provide security, the lack of a sufficiently trusted
directory can easily become bottleneck: breaking anything that relies
certificate-authority-based public key infrastructure requires breaking any one
certificate authority of attacker's choice[@EllisonSchneierPKI][@SchneierVerisignHacked] and a breach of the Kerberos domain
controller would result in a total compromise of the security domain. For this
reason, security-critical applications try to work around the need for a
dircetory service, for example ssh, OpenPGP, OTR and pond have users manually
communicate the critical bits of authenticating information to each other. This
approach is tedious[@arsTechnicaGGreenwaldPGP] and prone to human error, especially if the users in
question are not online at the same time [@Johnny]. Recently, better ways to
construct a user directory have been
discovered[@CertificateTransparancy][@SwartzNamecoin][@NameCoin]. However, all
of those rely on economic feedback loops for security, and the cost is passed on
to the users. We present `dename` -- a distributed user directory service with a
simpler security guarantee and lower projected operating costs.

# Overview

In essence, `dename` works by having a group of predetermined but independently
administered servers maintain identical copies of the user directory and
collectively vouching for the correctness of its contents. Now any one server
being honest is sufficient for an unanimous result to be correct. We have the
servers require updates to a user's profile to be digitally signed by that user,
thus preventing any other party (including the servers) from modifying it.
The following discussion of the operation of this system is organized as
follows: first, we describe how the servers communicate with each other to apply
changes to the directory while ensuring that they end up with exactly equal
results. In general, this is the problem of replicating a state machine in
presence of malicious faults, but our solution is significantly simpler than the
previous because it requires all parties to participate in order to make
progress.  Second, we describe the procedure of looking up users' profiles. We
start with a trivial but inefficient protocol and end up storing the directory
in a merkle-hashed radix tree and serving its branches. We argue that if a
lookup succeeds then the result must have been accepted by all servers. Third,
we tackle the issue of freshness, that is, we provide a system for ensuring that
the result actually represents the current state of the system. Fourth, we show
how independent verifiers can be added to this system in the spirit of
Certificate Transparency and SeqHash. Starting from the merkle tree data
structure described previously this addition is relatively straightforward and,
as a side effect, enables efficient coherent caching of lookup results.


# Maintaining consensus

\begin{figure}
\begin{msc}
msc {
  hscale = "0.65";

  a,b,c;

  b=>c [ label = "sigB(msgB)" ] ;
  b=>a [ label = "sigB(msgB)" ] ;
  a=>b [ label = "sigA(msgA)" ] ;
  a=>c [ label = "sigA(msgA)" ] ;
  c=>b [ label = "sigC(msgC)" ] ;
  c=>a [ label = "sigC(msgC)" ] ;
  ---  [ label = "Commitments done." ];
  b=>c [ label = "sigB(msgA, msgB, msgC)" ] ;
  b=>a [ label = "sigB(msgA, msgB, msgC)" ] ;
  a=>b [ label = "sigA(msgA, msgB, msgC)" ] ;
  a=>c [ label = "sigA(msgA, msgB, msgC)" ] ;
  c=>b [ label = "sigC(msgA, msgB, msgC)" ] ;
  c=>a [ label = "sigC(msgA, msgB, msgC)" ] ;
  ---  [ label = "Verify that all messages match." ];
}
\end{msc}
\caption{Verified broadcast}
\label{bcast}
\end{figure}

Changes to the user directory happen in discrete rounds, that is, every once in
a while servers propose changes and apply them in lockstep. We use a verified
broadcast primitive (described below) to ensure that all servers receive learn
the same set of requested changes and we make sure that the algorithm for handling
them is deterministic. Additionally, we describe unfair behavior servers could
engage in that would not directly violate the security claim but is nevertheless
undesirable and modify the protocol to counteract that.

The physical analogy of verified broadcast is a public announcement: everybody
learns what the announcer has to say and can be sure that others heard the same
thing. In computer networks allowing only point-to-point communication we can
emulate this using a two-phase protocol: first the announcer broadcasts the
message and then every server broadcasts an acknowledgment of what they received
from the announcer. In `dename`, all servers announce exactly one set of changes
during each round, so we can group each server's acknowledgments of all messages
it received into one message. Furthermore, as just the equality of the sets of
announcements received by different servers is important (not the actual
contents), we can use a cryptographic hash of all received announcements in an
acknowledgment instead of the announcements themselves. The verified broadcast
protocol can be seen in figure \ref{bcast}.

If two honest servers transition to a new state as a result of a round, they transition to the same state:
\begin{tabular}{c r}
$h(\text{inputs of A}) = h(\text{inputs of B})$\\
inputs of A = inputs of B\\
apply(state, inputs of A) = apply(stata, inputs of B)\\
\end{tabular}

In the description above, all messages are assumed to be authenticated. If one
server was able to impersonate another, it could fool it into thinking that a
different set of changes has been announced. We use digital signatures for
authentication because unlike faster symmetric authentication mechanisms,
signatures can be used to construct an audit trail in case one of the servers
sends out different announcements or acknowledgments during the same round.

The semantics of what kind of changes are allowed are in some sense a detail,
but they are not an unimportant one. For example, if one user could edit another
one's profile without their consent, the directory would be of little use. Out
implementation sets the following constraints:

1. All proposed profiles must contain a public key that can be used to verify
   digital signatures. To enforce this, all requests that are not signed with
   that key are denied.
2. If a name is not currently in use (does not map to a profile), all
   requests to make it map to a valid profile are accepted.
3. If a name already maps to a profile, requests to change it are only accepted
   if they are also signed with the current key in addition to the new one.

These rules ensure that if an user keeps their signing key secret, nobody else
can modify their profile. To free up names that for which the corresponding
secret key has been lost, we also allow expiration:

4. If the profile a name maps to has not been modified in the last $T_e$ rounds,
   the profile is automatically deleted.

: `dename` directory schema

| \small name | \small pubkey | \small profile | \small last modified |
|------|-----|---------|------|
| \small alice |  $pk_a$  | $\text{\texttt{22:}}pk_\text{ssh}\text{\texttt{,443:}} pk_\text{x509}$   |  2014-04-10   |
|  \small bob  |  $pk_b$ |  `25:bob@example`   | 2013-09-12  |


This requires users to confirm that they still use that profile by requesting a
nil change to it. The possibility of a profile expiring complicates the
situation because then somebody else may claim the name, but the old profile
still fits the criteria of being accepted by all servers -- this is the main
motivation for freshness assertions \ref{freshness}. It is, of course, possible
to have names not expire, but by our best judgment doing so would seriously
hamper the usability of the system when the space due to more and more names
pointing to profiles with lost keys.

The described rules of changing the directory are clearly sensitive to the order
in which changes are processed: it two servers propose two valid requests to
modify the same name in different ways, it is crucial to ensure that all servers
choose to apply them in the same order, because applying one of them may make
the other invalid. We use a standard protocol akin to [@XXXsharedRandomness] to
establish shared randomness between servers and use it to randomly pick an order
in which to process the changes.

However, a malicious server could observe the announcements other servers make
and deliberately introduce requests that conflict with some user's requests. To
prevent this, the requests are hashed before they are broadcast using the
verified broadcast protocol and actual requests are only revealed after every
server has announced the hash of their proposed changes. Now, all changes a
server proposes must be independent of the ones proposed by other servers
because it only gets to observe the other proposals after broadcasting its own.
To spread out network load, the current implementation actually pushes encrypted
requests to other servers before having received hashes from them and reveals
the encryption key to reveal the requests.
The final protocol is displayed in figure \ref{consensusProtocol}.

\begin{figure}
\begin{msc}
msc {
  hscale = "0.65";

  a,b,c;

  b=>c [ label = "sigB(h(rqsB)), enc(rqsB)" ] ;
  b=>a [ label = "sigB(h(rqsB)), enc(rqsB)" ] ;
  a=>b [ label = "sigA(h(rqsA)), enc(rqsA)" ] ;
  a=>c [ label = "sigA(h(rqsA)), enc(rqsA)" ] ;
  c=>b [ label = "sigC(h(rqsC)), enc(rqsC)" ] ;
  c=>a [ label = "sigC(h(rqsC)), enc(rqsC)" ] ;
  ---  [ label = "Commitments done." ];
  b=>c [ label = "sigB(h(hA, hB, hC))" ] ;
  b=>a [ label = "sigB(h(hA, hB, hC))" ] ;
  a=>b [ label = "sigA(h(hA, hB, hC))" ] ;
  a=>c [ label = "sigA(h(hA, hB, hC))" ] ;
  c=>b [ label = "sigC(h(hA, hB, hC))" ] ;
  c=>a [ label = "sigC(h(hA, hB, hC))" ] ;
  ---  [ label = "Verify that hX is unique forall X." ];
  b=>c [ label = "keyB" ] ;
  b=>a [ label = "keyB" ] ;
  a=>b [ label = "keyA" ] ;
  a=>c [ label = "keyA" ] ;
  c=>b [ label = "keyC" ] ;
  c=>a [ label = "keyC" ] ;
  ---  [ label = "Decrypt rqsX. Verify hX = h(rqsX). Process rqsX." ];
  b=>c [ label = "sigB(new state)" ] ;
  b=>a [ label = "sigB(new state)" ] ;
  a=>b [ label = "sigA(new state)" ] ;
  a=>c [ label = "sigA(new state)" ] ;
  c=>b [ label = "sigC(new state)" ] ;
  c=>a [ label = "sigC(new state)" ] ;
  ---  [ label = "Verify state consistent, serve to clients." ];
}
\end{msc}
\caption{\texttt{dename} consensus protocol}
\label{consensusProtocol}
\end{figure}

# Lookups

Simplistically, looking up a profile could be implemented by having the client
download the entire directory from each server and consider it correct if all
copies are equal. This reasoning relies on the assumption that at least one
server is honest.  This is, of course, completely impractical if there are
millions of users.  As an improvement on this, the client could instead download
the hash of the directory from all servers and the whole directory from one
server. If the hashes the servers reported are all equal to the hash of the
downloaded directory, the directory must be correct. This scheme is slightly
better, but still impractical.

What we need is mechanism to prove that a single name-profile pair is a part of
a larger directory with the given hash. Let's assume that the directory is
implemented as a prefix tree with profiles in the leaves. Now, every node in the
tree is augmented with a hash of its children. If the hash function is collision
resistant, each node uniquely determines the state of all names (and the
respective profiles) that start with the prefix this node corresponds to. The
root hash summarizes the whole directory.

To prove that a name-profile pair is a part of a directory with a known hash, a
server supplies the client with the list of hashes stored in the siblings of all
the nodes along the path from the leaf to the root (and an indication of whether
the siblings are to the left or the right of the path) -- the *Merkle hash
path*. To verify the proof, the client first hashes together the name and the
profile.  This hash is then hashed together with the server-provided hash stored
in the sibling of the leaf, resulting in the hash of their parent. This is
repeated recursively, hashing in the rest of the siblings all the way up to the
root. If the resulting root hash matches, the client knows the name indeed maps
to the given profile in the dictionary with the known root hash. As all servers
vouched for the whole dictionary and we are assuming that at least one of them
is honest, the profile must have been registered adhering to the requirements of
this system.

As an optimization, the servers can sign the root hash after each round and send
the signature to all other servers. This way, a client has to talk to only one
server to do a lookup but can still be assured that all servers agree about the
result after verifying the signatures.
The current implementation also uses the hash of a name instead of the name
itself in the prefix tree. This serves to keep the tree balanced and simplify
the implementation. As we assume hash collisions do not happen, this does not
change any other properties of the system

**Name absence proofs**: If a requested name is not in the tree, the server
can prove its absence by returning the name-identity pairs right before and
right after the missing name, as defined by the lexicographical order of the
dictionary keys, along with the associated Merkle hash pathes. The client has to
verify that both hash paths result give the correct root hash and that there
are indeed no nodes in between: up to their common ancestor, the former only has
left siblings and the latter only has right siblings.
*We have not implemented this mechanism.*

# Freshness

\label{freshness}
The protocol as described guarantees that if a client looks up a profile for a
name, this assignment must have been approved by all servers at some point in
time. However, nothing so far prevents it from being superseded by a later
change to the same profile. In this section we describe two mechanisms for
ensuring that the lookup result is *fresh* (not superseded). The more efficient
one requires the client and the servers to have a reasonably accurate clock,
without that there is an option to get a confirmation of freshness from each
server individually.


Each server will regularly (every $dt$ seconds) sign a *freshness assertion*
with the contents "As of time $t$, the most recent root hash is $H$".
The most recent assertion from each server will be distributed together with the
root hash. Before accepting a root hash as valid, the client will verify the
signatures on the freshness assertions and check that the timestamps are withing
$dt+\epsilon$ of its current time, where $\epsilon$ accounts for network latency
and uncertainty of the current time value.

Requiring all timestamps to match can be an availability problem: if any of the
servers is down, all lookups will fail. However, this requirement can be easily
relaxed: for any $f\ge0$ of the client's choice, it can check that at most $f$
of the timestamps are outside the allowed range and thus continue operating even
when $f$ servers are down.

Note that unlike in Spanner, the time uncertainty can be quite large for the
system to operate correctly. Even though future lookups by a machine that has
its clock within $\epsilon$ of all servers' clocks are only guaranteed to observe
that happened more than $dt+2\epsilon$ ago, we do not see it as a problem
because we expect security-critical changes to profiles to be rare and therefore
waiting after them to be acceptable. Proof of the $dt+2\epsilon$ bound: it will
take at most $dt$ for the new mapping to be timestamped by the servers, the
client will accept any mapping bearing a timstamp less than $\epsilon$ before
its own observed time (because its clock may be at most $\epsilon$ ahead), but
its clock may also be at most $\epsilon$ behind of the server time, in which case
it may end up accepting a mapping that was timestamped $2\epsilon$ ago.

In case a reasonably accurate clock source is not available, a client can still
look up the current profile for an username by contacting a set of servers such
that at least on of them can be assumed to be honest and requiring an unanimous
answer.

# Verifiers

We view having a fixed set of servers as a necessary evil: it is inherently a
central point of compromise, but the only alternative we know is to have the
evolution of the directory state determined by the entities that score highest
by some arbitrary metric, for the hashing power they control as in bitcoin and
namecoin. To mitigate this weakness, we provide an additional accountability
mechanism: everyone is welcome to observe how the state of the directory is
changed by the central servers, detect deviations from the set rules and, in
case of invalid changes being applied, have proof of wrongdoing on the servers'
part. We describe a *verifier* design that is significantly simpler (and
therefore more likely to be implemented correctly) than the servers themselves.
We also show how to leverage the merkle tree structure already used for lookups
to audit the changes made during an interval of time without ever having to
download the whole directory.

## The simple offline verifier

The purpose of the simple verifier design is to check that the core servers have
been enforcing the semantics of the directory. The design we describe here does
not aim to provide optimal throughput or responsiveness, instead we focus
on keeping the implementation as simple as possible with the hope that it can
therefore be widely audited and found confidence in.

The program takes as input a range of rounds starting with the very first one
(in the beginning of which the directory was empty) and for each round the
ordered sequence of changes considered by the core servers. It processes the
change requests in order, validating each one against the current state of the
directory and then updating the directory to reflect this change. At the end of
each round, it prints out the current hash of the merkle tree.

We implemented this verifier using 40 lines of readable python code and 20 lines
of `protobuf`[@protobuf] format specification. No custom libraries were used;
an in-memory implementation of the Merkle-tree is included in these 40 lines.

## Incremental verification

The system verification system described in the previous paragraph may be
simple, but it will become more and more costly as the total number of handled
requests increases. We wish to provide a mechanism through which independent
parties can participate in the verification of new changes made to the directory
without having to pay the up-front cost of downloading all past changes.
Naively omitting the old changes from the inputs of the simple verifier would not
yield a solution: it would have no way of determining whether a name has been
already registered or not. Instead, the core servers will supply the verifiers
with merkle-tree proofs about the relevant directory state in addition to the
requested changes. Specifically, each request to transfer some name will be
annotated with the old profile, its merkle path and all siblings used to
calculate the hashes for the new merkle path. The verifier will then use the
lookup procedure to verify the old mapping and calculate the new root hash using
the server-provided values instead of storing a local copy of the whole tree.
*We have not implemented this mechanism.*

## Coherent caching

# Implementation details

We implemented the `dename` server and client libraries in less than 4000 lines
of `go` using `postgresql` for storage. The current implementation is
a compromise between performance and understandability. For example, independent
tasks are done in parallel and in-process state is kept to eliminate redundant
database accesses and server signature verifications, but client signatures are
verified twice in some scenarios, batch signature verification is not used at
all and some invariants are enforced using expensive database byte array indexes
even though doing it manually is possible and has shown better performance.
Nonetheless, a laptop with a `Core 2 Duo L9400` cpu and a `Corsair Force GT` SSD
drive can handle 300 registrations per second, being just slightly disk-bound.
This number may not seem high when compared to non-cryptographic databases, but
when looked at as 800 million registrations per month, it is unlikely to become
a limiting factor in any realistic deployment scenario. Our implementation also
detects and reports various kinds of deviations from the specified protocol by
other servers even if ignoring them would be completely harmless -- this is
intended to assist with debugging and validation of possible other implementations.

## The consenus protocol

The protocol used to maintain verifiable consensus in a group of peers which may
include active adversaries is not specific to `dename` and can potentially be of
interest for other projects. We preserve this separation in the implementation:
a rough quarter of the codebase is made up by a reusable consensus library. The
library that waits for the application to submit operations to be handled and
calls an application-specified state transition function with the inputs chosen
for a single round whenever one is processed. Similarly, network communication
is implemented by the application and exposed to the library using a simple
`send(peer, data)` interface. However, persistence is currently handled by the
consensus library itself because the crash recovery procedure involves fairly
complicated queries to the consensus-specific state.

TODO: invariants of round states somewhere?

## Persistent Merkle radix tree

Daniel, please write this. Or if we do not want this section, remove it.

## Cryptography

No exotic cryptographic primitives are required for the operation of `dename`,
but because the choice of specific algorithms dictates performance and log size,
will describe our picks and the reasoning behind them. For all algorithms, we
required a security level of 128 bits and existsing adoption in real-world
systems.

- `ed25519` for digital signatures. Fast signature verification and small
  signature and public key size are essential for the performance of `dename`.
  Unlike other common digital signature schemes, `ed25519` supports even faster
  batch verification. - `sha256` for collision-resistant hashing and entropy
  extraction. Widely used, fast enough.
- `salsa20poly1305` encryption for concealing messages from servers during the
  commitment phase of a round. Any authenticated encryption scheme would work, chosen for simplicity.
- `salsa20` keystream for pseudo-random number generation to break ties
  between requested changes. Chosen for simplicity.

## Integration with existing systems

To show that it is practical to replace manual public key distribution with
`dename`, we integrated a `dename` client with the Pond asynchronous messaging
system and `ssh`. Modifying Pond to work with `dename` required changing 50
lines of logic code and 200 lines if user interface declarations; the two `ssh`
wrapper scripts are 2 lines each.

Pond requires each pair of users to establish a shared secret before they can
use Pond to communicate with each other. The Pond User Guide gives a detailed
explanation of several acceptable ways that may be used to establish a shared
secret, but despite the presence of instructions the intended users of Pond are
described as "the discerning". By our best understanding, exchanging public keys
between contacts is the limiting factor of Pond's usability. Our variant of
Pond[@PondDename] includes the necessary user interface for associating a Pond
account with a `dename` profile and adding contacts using their `dename` names
instead of shared secrets.

TODO: I would really like to claim that it is better
