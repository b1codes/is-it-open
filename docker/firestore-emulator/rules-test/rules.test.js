// ../firestore.rules must deny every direct client read and write: only the Django backend talks to
// Firestore, through the server client library, which bypasses the rules. These tests load the rules
// into the Firestore emulator and try each kind of access a Firebase client SDK could make, signed out
// and signed in, against the collections the backend uses.
//
//   docker compose up -d --wait firestore      # from the repo root
//   cd docker/firestore-emulator/rules-test && npm ci && npm test
//
// FIRESTORE_EMULATOR_HOST overrides where the emulator is (localhost:8080 by default).

import { readFileSync } from 'node:fs';
import { after, afterEach, before, beforeEach, describe, test } from 'node:test';
import assert from 'node:assert/strict';

import { assertFails, initializeTestEnvironment } from '@firebase/rules-unit-testing';
import {
  addDoc,
  collection,
  collectionGroup,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  limit,
  query,
  runTransaction,
  setDoc,
  setLogLevel,
  updateDoc,
  where,
  writeBatch,
} from 'firebase/firestore';

const RULES_PATH = new URL('../firestore.rules', import.meta.url);
const FIREBASE_JSON = new URL('../firebase.json', import.meta.url);
const [host, port] = (process.env.FIRESTORE_EMULATOR_HOST || 'localhost:8080').split(':');

// What the backend stores (apps/*/repository.py, services/firestore.py), seeded with the rules off.
const USER = 'alice';
const SEED = {
  [`users/${USER}`]: { username: USER, token: 'local-api-token', password: 'pbkdf2_sha256$...' },
  [`users/${USER}/saved_places/place-1`]: { place_id: 1, is_pinned: false },
  'places/place-1': { id: 1, name: "Joe's Pizza", tomtom_id: 'place-1' },
  'counters/places': { next: 2 },
};
const DOCS = Object.keys(SEED);
const COLLECTIONS = ['users', `users/${USER}/saved_places`, 'places', 'counters'];

// Who might call: signed out, a signed-in user (including the owner of users/alice), and tokens
// with claims a rule might be tempted to trust.
const CALLERS = {
  'signed out': (env) => env.unauthenticatedContext(),
  'signed in': (env) => env.authenticatedContext('mallory'),
  'signed in as the document owner': (env) => env.authenticatedContext(USER),
  'signed in with a verified email': (env) =>
    env.authenticatedContext('mallory', { email: 'mallory@example.com', email_verified: true }),
  'signed in with an admin claim': (env) => env.authenticatedContext('mallory', { admin: true }),
};

let env;

before(async () => {
  // The SDK logs every refused write; the assertions already check them.
  setLogLevel('silent');
  env = await initializeTestEnvironment({
    projectId: 'demo-is-it-open-rules-test',
    firestore: { rules: readFileSync(RULES_PATH, 'utf8'), host, port: Number(port) },
  });
});

beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await Promise.all(Object.entries(SEED).map(([path, data]) => setDoc(doc(db, path), data)));
  });
});

after(async () => {
  await env?.cleanup();
});

test('the emulator and `firebase deploy` use these rules', () => {
  assert.equal(JSON.parse(readFileSync(FIREBASE_JSON, 'utf8')).firestore.rules, 'firestore.rules');
});

test('the seeded documents exist, so a denied read is the rules and not a missing document', async () => {
  await env.withSecurityRulesDisabled(async (context) => {
    for (const path of DOCS) {
      assert.ok((await getDoc(doc(context.firestore(), path))).exists(), path);
    }
  });
});

for (const [caller, contextFor] of Object.entries(CALLERS)) {
  describe(caller, () => {
    let db;
    beforeEach(() => {
      db = contextFor(env).firestore();
    });

    // A refused write must not have changed anything.
    afterEach(async () => {
      await env.withSecurityRulesDisabled(async (context) => {
        const admin = context.firestore();
        for (const [path, data] of Object.entries(SEED)) {
          assert.deepEqual((await getDoc(doc(admin, path))).data(), data, path);
        }
        for (const path of [...COLLECTIONS, 'anything']) {
          const expected = DOCS.filter((d) => d.startsWith(`${path}/`) && d.split('/').length === path.split('/').length + 1);
          assert.equal((await getDocs(collection(admin, path))).size, expected.length, path);
        }
      });
    });

    for (const path of DOCS) {
      test(`can't read ${path}`, async () => {
        await assertFails(getDoc(doc(db, path)));
      });

      test(`can't overwrite, update or delete ${path}`, async () => {
        await assertFails(setDoc(doc(db, path), { hacked: true }));
        await assertFails(setDoc(doc(db, path), { hacked: true }, { merge: true }));
        await assertFails(updateDoc(doc(db, path), { hacked: true }));
        await assertFails(deleteDoc(doc(db, path)));
      });
    }

    for (const path of COLLECTIONS) {
      test(`can't list or query ${path}`, async () => {
        await assertFails(getDocs(collection(db, path)));
        await assertFails(getDocs(query(collection(db, path), limit(1))));
        await assertFails(getDocs(query(collection(db, path), where('id', '==', 1))));
      });

      test(`can't create documents in ${path}`, async () => {
        await assertFails(addDoc(collection(db, path), { created: true }));
        await assertFails(setDoc(doc(db, path, 'new-doc'), { created: true }));
      });
    }

    test("can't query every user's saved places at once (collection group)", async () => {
      await assertFails(getDocs(collectionGroup(db, 'saved_places')));
    });

    test("can't read a missing document or write a collection the backend doesn't use", async () => {
      await assertFails(getDoc(doc(db, 'users/nobody')));
      await assertFails(setDoc(doc(db, 'anything/at-all'), { created: true }));
      await assertFails(setDoc(doc(db, 'anything/at-all/deeply/nested'), { created: true }));
    });

    test("can't write in a batch or a transaction", async () => {
      const batch = writeBatch(db);
      batch.set(doc(db, 'places/place-2'), { name: 'Injected' });
      await assertFails(batch.commit());

      await assertFails(
        runTransaction(db, async (transaction) => {
          transaction.set(doc(db, 'counters/places'), { next: 0 });
        }),
      );
    });
  });
}
