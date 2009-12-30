# Models a CouchDB document containing a single file attachment with a bit of
# metadata about the file.
#
class StoredFile < CouchRest::ExtendedDocument

  property :_id
  property :internal_id
  property :size_bytes
  property :filename
  property :mime_type

  view_by :internal_id

  # A special attachment "File" is expected to exist

end

