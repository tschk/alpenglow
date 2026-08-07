#[test]
fn test_tar() {
    let mut tar_builder = tar::Builder::new(Vec::new());

    // GNU Long name extension where the long name data is too short or invalid
    let mut ext_header = tar::Header::new_gnu();
    ext_header.set_size(100);
    ext_header.set_entry_type(tar::EntryType::GNULongName);
    ext_header.set_cksum();
    // But we don't append enough data to satisfy the size
    let res = tar_builder.append_data(&mut ext_header, "././@LongLink", b"short".as_ref());
    assert!(res.is_err(), "append_data didn't return err!");
}
