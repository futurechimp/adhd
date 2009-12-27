class ContentDoc < CouchRest::ExtendedDocument
  # NOTE: NO DEFAULT DATABASE IN THE OBJECT -- WE WILL BE STORING A LOT OF
  # DATABASES OF THIS TYPE.


  property :_id
  property :internal_id
  property :size_bytes
  property :filename
  property :mime_type

  view_by :internal_id

  # A special attachment "File" is expected to exist

end

