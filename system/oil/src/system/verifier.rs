//! APK signature verification via CMS/PKCS#7 + RSA.
//!
//! Alpine .apk packages embed a CMS SignedData detached signature
//! (`.SIGN.RSA.<keyname>`) in the first gzip stream. The signature
//! authenticates the decompressed data tar (third gzip stream). Public
//! keys live in `/etc/apk/keys/<keyname>.pub` as PEM-encoded RSA keys.

use cms::signed_data::SignedData;
use der::{Decode, Encode};
use rsa::pkcs1v15;
use rsa::pkcs1v15::Signature;
use rsa::pkcs8::DecodePublicKey;
use rsa::RsaPublicKey;
use sha1::Sha1;
use sha2::{Digest, Sha256};
use signature::hazmat::PrehashVerifier;

use crate::error::{OilError, Result};

// Digest algorithm OIDs
const OID_SHA256: const_oid::ObjectIdentifier =
    const_oid::ObjectIdentifier::new_unwrap("2.16.840.1.101.3.4.2.1");
const OID_SHA1: const_oid::ObjectIdentifier =
    const_oid::ObjectIdentifier::new_unwrap("1.3.14.3.2.26");
// Signature algorithm OIDs (shaXWithRSAEncryption)
const OID_RSA_SHA256: const_oid::ObjectIdentifier =
    const_oid::ObjectIdentifier::new_unwrap("1.2.840.113549.1.1.11");
const OID_RSA_SHA1: const_oid::ObjectIdentifier =
    const_oid::ObjectIdentifier::new_unwrap("1.2.840.113549.1.1.5");
// CMS attribute OIDs
const OID_MD: const_oid::ObjectIdentifier =
    const_oid::ObjectIdentifier::new_unwrap("1.2.840.113549.1.9.4");

/// Verify a detached CMS signature against data using a PEM-encoded RSA public key.
pub fn verify_apk_signature(data_tar: &[u8], sig_cms_der: &[u8], pubkey_pem: &str) -> Result<()> {
    let signed_data = SignedData::from_der(sig_cms_der)
        .map_err(|e| OilError::Install(format!("bad CMS signature: {e}")))?;

    let signer = signed_data
        .signer_infos
        .0
        .get(0)
        .ok_or_else(|| OilError::Install("CMS signature has no signer".into()))?;

    let sig_bytes = signer.signature.as_bytes();
    let sig_alg = signer.signature_algorithm.oid;
    let digest_alg = signer.digest_alg.oid;

    // Hash the data tar content using the CMS digest algorithm
    let data_hash: Vec<u8> = if digest_alg == OID_SHA256 {
        Sha256::digest(data_tar).to_vec()
    } else if digest_alg == OID_SHA1 {
        Sha1::digest(data_tar).to_vec()
    } else {
        return Err(OilError::Install("unsupported CMS digest algorithm".into()));
    };

    // Determine what the RSA signature authenticates — this depends on
    // whether CMS signed attributes (signedAttrs) are present.
    //
    // With signedAttrs:  prehash = H(DER(signedAttrs))   where H comes from
    //                                            the signatureAlgorithm.
    //                   The attrs contain a messageDigest that must match
    //                   our locally computed data_hash.
    // Without signedAttrs:  prehash = data_hash  (the raw content hash).
    let prehash = if let Some(attrs) = &signer.signed_attrs {
        verify_message_digest(attrs, &data_hash)?;
        let mut encoded = Vec::new();
        attrs
            .encode_to_vec(&mut encoded)
            .map_err(|e| OilError::Install(format!("encode attrs: {e}")))?;
        // ponytail: hash DER(attrs) according to signatureAlgorithm
        hash_bytes(&encoded, sig_alg)?
    } else {
        data_hash
    };

    // Load RSA public key
    let pubkey = RsaPublicKey::from_public_key_pem(pubkey_pem)
        .map_err(|e| OilError::Install(format!("bad public key: {e}")))?;

    // Verify PKCS#1 v1.5 signature using the correct hash
    let sig = Signature::try_from(sig_bytes)
        .map_err(|e| OilError::Install(format!("bad signature bytes: {e}")))?;

    if sig_alg == OID_RSA_SHA256 {
        let vk = pkcs1v15::VerifyingKey::<Sha256>::new_unprefixed(pubkey);
        vk.verify_prehash(&prehash, &sig)
            .map_err(verification_failed)
    } else if sig_alg == OID_RSA_SHA1 {
        let vk = pkcs1v15::VerifyingKey::<Sha1>::new_unprefixed(pubkey);
        vk.verify_prehash(&prehash, &sig)
            .map_err(verification_failed)
    } else {
        Err(OilError::Install(
            "unsupported RSA signature algorithm".into(),
        ))
    }
}

fn hash_bytes(data: &[u8], sig_alg: const_oid::ObjectIdentifier) -> Result<Vec<u8>> {
    if sig_alg == OID_RSA_SHA256 {
        Ok(Sha256::digest(data).to_vec())
    } else if sig_alg == OID_RSA_SHA1 {
        Ok(Sha1::digest(data).to_vec())
    } else {
        Err(OilError::Install(
            "unsupported signature hash algorithm".into(),
        ))
    }
}

fn verification_failed(e: signature::Error) -> OilError {
    OilError::ChecksumMismatch {
        expected: "valid signature".into(),
        actual: format!("RSA verification failed: {e}"),
    }
}

/// Check that the signed-attributes SET contains a messageDigest matching
/// our locally computed hash.
fn verify_message_digest(
    attrs: &cms::signed_data::SignedAttributes,
    computed_hash: &[u8],
) -> Result<()> {
    for attr in attrs.iter() {
        if attr.oid != OID_MD {
            continue;
        }
        for val in attr.values.iter() {
            if let Ok(octet) = val.decode_as::<der::asn1::OctetString>() {
                if octet.as_bytes() == computed_hash {
                    return Ok(());
                }
            }
        }
    }

    Err(OilError::ChecksumMismatch {
        expected: hex::encode(computed_hash),
        actual: "messageDigest in CMS signedAttrs does not match".into(),
    })
}
