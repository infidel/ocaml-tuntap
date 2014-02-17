(*
 * Copyright (c) 2010-2013 Anil Madhavapeddy <anil@recoil.org>
 * Copyright (c) 2013 Vincent Bernardoff <vb@luminar.eu.org>
 *
 * Permission to use, copy, modify, and distribute this software for any
 * purpose with or without fee is hereby granted, provided that the above
 * copyright notice and this permission notice appear in all copies.
 *
 * THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 * WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
 * ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 * WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
 * ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
 * OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 *)

type kind = Tap | Tun

external opentun_stub : string -> kind -> bool -> bool
  -> int -> int -> Unix.file_descr * string = "tun_opendev_byte" "tun_opendev"
external get_macaddr : string -> string = "get_macaddr"
external set_ipv4 : string -> string -> string -> unit = "set_ipv4"
external set_up_and_running : string -> unit = "set_up_and_running"

external get_ifnamsiz : unit -> int = "get_ifnamsiz"

let open_ kind ?(pi=false) ?(persist=false)
    ?(user = -1) ?(group = -1) ?(devname="") () =
  opentun_stub devname kind pi persist user group

let opentun = open_ Tun
let opentap = open_ Tap

(* Closing is just opening an existing device in non-persistent
   mode *)
let closetun devname = ignore (opentun ~devname ())
let closetap devname = ignore (opentap ~devname ())

let set_ipaddr ?(netmask=0) devname =
  let open Ipaddr in
  function
  | V4 a ->
    set_ipv4 devname (V4.to_string a) V4.(to_string (Prefix.mask netmask))
  | V6 a -> raise (Invalid_argument "Setting IPv6 addresses is currenctly unsupported")

let get_macaddr iface = Macaddr.of_bytes_exn (get_macaddr iface)

type ifaddr_ = {
  name_: string;
  sa_family_: int;
  addr_: string option;
  mask_: string option;
  brd_:  string option;
}

type ifaddrs_ptr

type ipaddr =
  | AF_INET of Ipaddr.V4.t * Ipaddr.V4.Prefix.t
  | AF_INET6 of Ipaddr.V6.t * Ipaddr.V6.Prefix.t

type ifaddr = {
  name: string;
  ipaddr: ipaddr
}

external getifaddrs_stub : unit -> ifaddrs_ptr option = "getifaddrs_stub"
external freeifaddrs_stub : ifaddrs_ptr -> unit = "freeifaddrs_stub"

external iface_get : ifaddrs_ptr -> ifaddr_ = "iface_get"
external iface_next : ifaddrs_ptr -> ifaddrs_ptr option = "iface_next"

module Opt = struct
  type 'a t = 'a option
  let (>>=) x f = match x with Some v -> f v | None -> None
  let (>|=) x f = match x with Some v -> Some (f v) | None -> None
  let run = function
    | Some x -> x
    | None -> raise Not_found
end

let ifaddr_of_ifaddr_ ifaddr_ =
  let open Ipaddr in
  let open Opt in
  match ifaddr_.sa_family_ with
  | 0 ->
    let addr = ifaddr_.addr_ >|= fun v -> (V4.of_bytes_exn v)
    and nmask = ifaddr_.mask_ >|= fun v -> (V4.of_bytes_exn v)
    in
    Some {
      name = ifaddr_.name_;
      ipaddr = AF_INET ((run addr), V4.Prefix.(of_netmask (run nmask) (run addr)))
    }
  | 1 ->
    let addr = ifaddr_.addr_ >|= fun v -> (V6.of_bytes_exn v)
    and nmask = ifaddr_.mask_ >|= fun v -> (V6.of_bytes_exn v)
    in
    Some {
      name = ifaddr_.name_;
      ipaddr = AF_INET6 ((run addr), V6.Prefix.(of_netmask (run nmask) (run addr)))
    }
  | _ -> None

let getifaddrs () =
  match getifaddrs_stub () with
  | None -> []
  | Some start ->
    let rec loop acc ptr =
      let acc = match ifaddr_of_ifaddr_ (iface_get ptr) with
        | Some p -> p::acc
        | None -> acc in
      match iface_next ptr with
      | None ->
        freeifaddrs_stub start;
        acc
      | Some p ->
        loop acc p
    in
    loop [] start
