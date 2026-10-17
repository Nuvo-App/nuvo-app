// Result of a conditional GET (If-None-Match). [data] is null on a 304
// ("not modified"); otherwise it is the parsed body and [etag] is the
// response ETag (null when the server sends none). [raw] is the decoded JSON
// the model was parsed from, kept so it can be persisted and rehydrated
// exactly.
class Conditional<T> {
  const Conditional({this.data, this.etag, this.raw});

  const Conditional.notModified({this.etag}) : data = null, raw = null;

  final T? data;
  final String? etag;
  final Object? raw;

  bool get notModified => data == null;
}
