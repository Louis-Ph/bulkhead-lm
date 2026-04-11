type encrypted_credentials =
  { token : string
  ; encoding_aes_key : string
  ; app_id : string
  }

type encrypted_reply =
  { encrypted : string
  ; msg_signature : string
  ; timestamp : string
  ; nonce : string
  }

let aes_key_encoded_length = 43
let aes_key_size_bytes = 32
let random_prefix_size_bytes = 16
let message_length_size_bytes = 4
let initial_vector_size_bytes = 16
let pkcs7_block_size_bytes = 32
let rng_initialized = Lazy.from_fun (fun () -> Mirage_crypto_rng_unix.use_default ())

let secure_random_bytes length =
  Lazy.force rng_initialized;
  Mirage_crypto_rng.generate length
;;

let hex_encode value =
  let digits = "0123456789abcdef" in
  let length = String.length value in
  let encoded = Bytes.create (length * 2) in
  for index = 0 to length - 1 do
    let code = Char.code value.[index] in
    Bytes.set encoded (index * 2) digits.[code lsr 4];
    Bytes.set encoded ((index * 2) + 1) digits.[code land 0x0F]
  done;
  Bytes.unsafe_to_string encoded
;;

let random_nonce () = secure_random_bytes 8 |> hex_encode

let sha1_signature parts =
  parts
  |> List.sort String.compare
  |> String.concat ""
  |> Digestif.SHA1.digest_string
  |> Digestif.SHA1.to_hex
;;

let ciphertext_signature ~token ~timestamp ~nonce ~encrypted =
  sha1_signature [ token; timestamp; nonce; encrypted ]
;;

let current_unix_timestamp_string () = Unix.time () |> int_of_float |> string_of_int

let pkcs7_pad value =
  let remainder = String.length value mod pkcs7_block_size_bytes in
  let padding =
    if remainder = 0 then pkcs7_block_size_bytes else pkcs7_block_size_bytes - remainder
  in
  value ^ String.make padding (Char.chr padding)
;;

let pkcs7_unpad value =
  let length = String.length value in
  if length = 0
  then
    Error
      (Domain_error.invalid_request
         "WeChat encrypted payload is empty after AES decryption.")
  else (
    let padding = Char.code value.[length - 1] in
    if padding < 1 || padding > pkcs7_block_size_bytes || padding > length
    then
      Error
        (Domain_error.invalid_request
           "WeChat encrypted payload has invalid PKCS#7 padding.")
    else (
      let rec verify index =
        if index = padding
        then Ok (String.sub value 0 (length - padding))
        else if Char.code value.[length - index - 1] <> padding
        then
          Error
            (Domain_error.invalid_request
               "WeChat encrypted payload has invalid PKCS#7 padding.")
        else verify (index + 1)
      in
      verify 0))
;;

let encode_network_uint32 value =
  let encoded = Bytes.create message_length_size_bytes in
  Bytes.set encoded 0 (Char.chr ((value lsr 24) land 0xFF));
  Bytes.set encoded 1 (Char.chr ((value lsr 16) land 0xFF));
  Bytes.set encoded 2 (Char.chr ((value lsr 8) land 0xFF));
  Bytes.set encoded 3 (Char.chr (value land 0xFF));
  Bytes.unsafe_to_string encoded
;;

let decode_network_uint32 value =
  if String.length value <> message_length_size_bytes
  then
    Error
      (Domain_error.invalid_request
         "WeChat encrypted payload is missing the 4-byte message length.")
  else
    Ok
      ((Char.code value.[0] lsl 24)
       lor (Char.code value.[1] lsl 16)
       lor (Char.code value.[2] lsl 8)
       lor Char.code value.[3])
;;

let decode_aes_key encoding_aes_key =
  if String.length encoding_aes_key <> aes_key_encoded_length
  then
    Error
      (Domain_error.invalid_request
         "WeChat EncodingAESKey must be exactly 43 characters long.")
  else (
    match Base64.decode (encoding_aes_key ^ "=") with
    | Ok aes_key when String.length aes_key = aes_key_size_bytes -> Ok aes_key
    | Ok _ ->
      Error
        (Domain_error.invalid_request
           "WeChat EncodingAESKey does not decode to 32 bytes.")
    | Error (`Msg message) ->
      Error
        (Domain_error.invalid_request
           ("WeChat EncodingAESKey is not valid base64: " ^ message)))
;;

let decrypt_payload ~(credentials : encrypted_credentials) ~encrypted =
  Result.bind (decode_aes_key credentials.encoding_aes_key) (fun aes_key ->
    match Base64.decode encrypted with
    | Error (`Msg message) ->
      Error
        (Domain_error.invalid_request
           ("WeChat encrypted payload is not valid base64: " ^ message))
    | Ok ciphertext ->
      let key = Mirage_crypto.AES.CBC.of_secret aes_key in
      let iv = String.sub aes_key 0 initial_vector_size_bytes in
      let plaintext = Mirage_crypto.AES.CBC.decrypt ~key ~iv ciphertext in
      Result.bind (pkcs7_unpad plaintext) (fun unpadded ->
        let minimum_length = random_prefix_size_bytes + message_length_size_bytes in
        if String.length unpadded < minimum_length
        then
          Error
            (Domain_error.invalid_request
               "WeChat encrypted payload is shorter than the required header.")
        else (
          let encoded_length =
            String.sub unpadded random_prefix_size_bytes message_length_size_bytes
          in
          match decode_network_uint32 encoded_length with
          | Error _ as error -> error
          | Ok message_length ->
            let message_offset = random_prefix_size_bytes + message_length_size_bytes in
            let app_id_offset = message_offset + message_length in
            if app_id_offset > String.length unpadded
            then
              Error
                (Domain_error.invalid_request
                   "WeChat encrypted payload length prefix exceeds the decrypted body.")
            else (
              let message = String.sub unpadded message_offset message_length in
              let app_id =
                String.sub unpadded app_id_offset (String.length unpadded - app_id_offset)
              in
              if String.equal app_id credentials.app_id
              then Ok message
              else
                Error
                  (Domain_error.operation_denied
                     "WeChat encrypted payload app id mismatch.")))))
;;

let encrypt_payload ?random_prefix ~(credentials : encrypted_credentials) ~plaintext () =
  Result.map
    (fun aes_key ->
      let prefix =
        match random_prefix with
        | Some value when String.length value = random_prefix_size_bytes -> value
        | Some _ -> invalid_arg "WeChat random_prefix must be 16 bytes."
        | None -> secure_random_bytes random_prefix_size_bytes
      in
      let full_plaintext =
        String.concat
          ""
          [ prefix
          ; encode_network_uint32 (String.length plaintext)
          ; plaintext
          ; credentials.app_id
          ]
      in
      let padded = pkcs7_pad full_plaintext in
      let key = Mirage_crypto.AES.CBC.of_secret aes_key in
      let iv = String.sub aes_key 0 initial_vector_size_bytes in
      Mirage_crypto.AES.CBC.encrypt ~key ~iv padded |> Base64.encode_exn)
    (decode_aes_key credentials.encoding_aes_key)
;;

let encrypt_reply
  ?random_prefix
  ?timestamp
  ?nonce
  ~(credentials : encrypted_credentials)
  ~plaintext
  ()
  =
  let timestamp = Option.value timestamp ~default:(current_unix_timestamp_string ()) in
  let nonce = Option.value nonce ~default:(random_nonce ()) in
  encrypt_payload ?random_prefix ~credentials ~plaintext ()
  |> Result.map (fun encrypted ->
    { encrypted
    ; msg_signature =
        ciphertext_signature ~token:credentials.token ~timestamp ~nonce ~encrypted
    ; timestamp
    ; nonce
    })
;;
