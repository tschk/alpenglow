sed -i -e '/let prehash = if let Some(attrs) = &signer.signed_attrs {/,/};/c\    let prehash = calculate_prehash(signer, data_hash, sig_alg)?;' system/oil/src/system/verifier.rs
sed -i -e '/fn hash_bytes/i \
/// Determine what the RSA signature authenticates — this depends on\
/// whether CMS signed attributes (signedAttrs) are present.\
///\
/// With signedAttrs:  prehash = H(DER(signedAttrs))   where H comes from\
///                                            the signatureAlgorithm.\
///                   The attrs contain a messageDigest that must match\
///                   our locally computed data_hash.\
/// Without signedAttrs:  prehash = data_hash  (the raw content hash).\
fn calculate_prehash(\
    signer: &cms::signed_data::SignerInfo,\
    data_hash: Vec<u8>,\
    sig_alg: const_oid::ObjectIdentifier,\
) -> Result<Vec<u8>> {\
    if let Some(attrs) = &signer.signed_attrs {\
        verify_message_digest(attrs, &data_hash)?;\
        let mut encoded = Vec::new();\
        attrs\
            .encode_to_vec(&mut encoded)\
            .map_err(|e| OilError::Install(format!("encode attrs: {e}")))?;\
        // ponytail: hash DER(attrs) according to signatureAlgorithm\
        hash_bytes(&encoded, sig_alg)\
    } else {\
        Ok(data_hash)\
    }\
}\
' system/oil/src/system/verifier.rs
