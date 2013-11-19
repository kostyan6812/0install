(* Copyright (C) 2013, Thomas Leonard
 * See the README file for details, or visit http://0install.net.
 *)

(** Generic code for interacting with distribution package managers. *)

(** Passed to [distribution#get_package_impls]. It provides details of the query and a place to collect the results. *)
type query = {
  elem : Support.Qdom.element;      (* The <package-element> which generated this query *)
  package_name : string;            (* The 'package' attribute on the <package-element> *)
  elem_props : Feed.properties;     (* Properties on or inherited by the <package-element> - used by [add_package_implementation] *)
  feed : Feed.feed;                 (* The feed containing the <package-element> *)
  results : Feed.implementation Support.Common.StringMap.t ref;
}

class virtual distribution : General.config ->
  object
    val virtual distro_name : string

    (** All IDs will start with this string (e.g. "package:deb") *)
    val virtual id_prefix : string

    (** Paths to search for missing binaries (i.e. the platform default for $PATH) *)
    val system_paths : string list

    val packagekit : Packagekit.packagekit

    (** Can we use packages for this distribution? For example, MacPortsDistribution can use "MacPorts" and "Darwin" packages. *)
    method match_name : string -> bool

    (** Test whether this <selection> element is still valid. The default implementation tries to load the feed from the
     * feed cache, calls [distribution#get_impls_for_feed] on it and checks whether the required implementation ID is in the
     * returned map. Override this if you can provide a more efficient implementation. *)
    method is_installed : Support.Qdom.element -> bool

    (** Add the implementations for this feed to [query].
     * Called by [get_impls_for_feed] once for each <package-implementation> element.
     * This default implementation adds anything found previously by PackageKit. *)
    method private get_package_impls : query -> unit

    (** Get the native implementations (installed or candidates for installation) for this feed.
     * This default implementation finds the best <package-implementation> elements and calls [get_package_impls] on each one. *)
    method get_impls_for_feed : Feed.feed -> Feed.implementation Support.Common.StringMap.t

    (** Check (asynchronously) for available but currently uninstalled candidates. Once the returned
        promise resolves, the candidates should be included in future responses from [get_package_impls]. *)
    method check_for_candidates : Feed.feed -> unit Lwt.t

    (** Install a set of packages of a given type (as set previously by [check_for_candidates]).
     * Normally called only by the [Distro.install_distro_packages] function. *)
    method install_distro_packages : Ui.ui_handler -> string -> (Feed.implementation * Feed.distro_retrieval_method) list -> [ `ok | `cancel ] Lwt.t

    (** Called when an installed package is added, or when installation completes, to find the correct main value,
     * since we might not be able to work it out before-hand. The default checks that the path exists and, if not,
     * searches [system_paths] for it.
     * Note: Only called if the implementation already has a "run" command. *)
    method private get_correct_main : Feed.implementation -> Feed.command -> Support.Common.filepath option

    (** Add a new Feed.implementation result to [query]. *)
    method private add_package_implementation :
      ?main:string ->
      ?retrieval_method:(Feed.distro_retrieval_method) ->
      query ->
      id:string ->
      version:string ->
      machine:(string option) ->
      extra_attrs:((string * string) list) ->
      is_installed:bool ->
      distro_name:string ->
      unit
  end

(** Call the old Python code where we're currently missing support in OCaml.
 * Overrides [get_impls_for_feed] to include host Python details (if [check_host_python] is set).
 * Overrides [get_package_impls] to include results from [add_package_impls_from_python]. *)
class virtual python_fallback_distribution : Python.slave -> string -> string list ->
  object
    inherit distribution

    (* Should we check for Python and GObject manually? Use [false] if the package manager
     * can be relied upon to find them. *)
    val virtual check_host_python : bool

    (** Query the Python slave and add any implementations returned. Override this if you can sometimes skip this step. *)
    method private add_package_impls_from_python : query -> unit
  end

(** Check whether this <selection> is still valid. If the quick-test-* attributes are present, we use
    them to check. Otherwise, we call [distribution#is_installed]. *)
val is_installed : General.config -> distribution -> Support.Qdom.element -> bool

(** Install these packages using the distribution's package manager.
 * Sorts the implementations into groups by their type and then calls [distribution#install_distro_packages] once for each group. *)
val install_distro_packages : distribution -> Ui.ui_handler -> Feed.implementation list -> [ `ok | `cancel ] Lwt.t

(** Return the <package-implementation> elements that best match this distribution. *)
val get_matching_package_impls : distribution -> Feed.feed -> (Support.Qdom.element * Feed.properties) list