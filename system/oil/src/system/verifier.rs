//! APK v2 signature verification.
//!
//! An Alpine `.apk` is three concatenated gzip members: signature, control
//! and data. abuild signs the *compressed* control member with
//! `openssl dgst -sign`, so `.SIGN.RSA.<key>` holds a raw RSA PKCS#1 v1.5
//! signature over SHA-1 of those bytes (`.SIGN.RSA256.<key>` uses SHA-256).
//! The control member's `.PKGINFO` then pins the data member through
//! `datahash`, the SHA-256 of the compressed data member. `<key>` is the
//! full public key filename, e.g. `alpine-devel@lists.alpinelinux.org-6165ee59.rsa.pub`.

use rsa::pkcs1v15::{Signature, VerifyingKey};
use rsa::pkcs8::DecodePublicKey;
use rsa::RsaPublicKey;
use sha1::Sha1;
use sha2::{Digest, Sha256};
use signature::Verifier;

use crate::error::{OilError, Result};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum SigHash {
    Sha1,
    Sha256,
}

/// Verify a raw RSA PKCS#1 v1.5 signature over `message` with a PEM public key.
pub fn verify_rsa_signature(
    message: &[u8],
    signature: &[u8],
    hash: SigHash,
    pubkey_pem: &str,
) -> Result<()> {
    let pubkey = RsaPublicKey::from_public_key_pem(pubkey_pem)
        .map_err(|e| OilError::Install(format!("bad public key: {e}")))?;
    let sig = Signature::try_from(signature)
        .map_err(|e| OilError::Install(format!("bad signature bytes: {e}")))?;
    let verified = match hash {
        SigHash::Sha1 => VerifyingKey::<Sha1>::new(pubkey).verify(message, &sig),
        SigHash::Sha256 => VerifyingKey::<Sha256>::new(pubkey).verify(message, &sig),
    };
    verified.map_err(|e| OilError::ChecksumMismatch {
        expected: "valid signature".into(),
        actual: format!("RSA verification failed: {e}"),
    })
}

/// Check the compressed data member against the `datahash` from `.PKGINFO`.
pub fn verify_datahash(data_member: &[u8], datahash_hex: &str) -> Result<()> {
    let actual = hex::encode(Sha256::digest(data_member));
    let expected = datahash_hex.trim().to_ascii_lowercase();
    if actual == expected {
        Ok(())
    } else {
        Err(OilError::ChecksumMismatch { expected, actual })
    }
}
