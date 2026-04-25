let repository_marker = "config/defaults/security_policy.json"

let repo_root () =
  let rec search path =
    if Sys.file_exists (Filename.concat path repository_marker)
    then path
    else (
      let parent = Filename.dirname path in
      if String.equal parent path then failwith "unable to locate repository root";
      search parent)
  in
  search (Sys.getcwd ())
;;

let config_path relative_path = Filename.concat (repo_root ()) relative_path
