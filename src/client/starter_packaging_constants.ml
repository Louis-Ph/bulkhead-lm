module Command = struct
  let package = "/package"
end

module Defaults = struct
  let package_name = "bulkhead-lm"
  let display_name = "BulkheadLM"
  let description =
    "BulkheadLM secure OCaml gateway with starter, worker, and provider routing."
  ;;

  let artifact_dir = "dist"
end

module Text = struct
  let package_intro =
    "The packaging assistant will prepare a distributable package for this operating system and will guide you step by step."
  ;;

  let package_done artifact_path =
    Fmt.str "Package build succeeded. Artifact: %s" artifact_path
  ;;

  let package_failed =
    "Package build failed. You can adjust the settings and try again."
  ;;

  let unsupported_os =
    "Packaging is currently supported only on macOS, Ubuntu, and FreeBSD."
  ;;
end
