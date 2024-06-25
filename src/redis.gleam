import argv
import birl
import birl/duration
import gleam/bit_array
import gleam/bytes_builder
import gleam/dict
import gleam/erlang/process
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order.{Gt}
import gleam/otp/actor
import gleam/result
import gleam/string
import glisten.{Packet}

type State =
  dict.Dict(String, #(String, Option(birl.Time)))

fn args_kv(args, k) {
  case list.drop_while(args, fn(key) { k != key }) {
    [key, value, ..] if k == key -> Ok(value)
    _ -> Error(Nil)
  }
}

const replication_id = "8371b4fb1155b71f4a04d3e1bc3e18c4a990aeeb"

const offset = 0

pub fn main() {
  io.println("Logs from your program will appear here!")

  let args = argv.load().arguments

  let port =
    args |> args_kv("--port") |> result.then(int.parse) |> result.unwrap(6379)

  let replicaof =
    args |> args_kv("--replicaof") |> result.map(Some) |> result.unwrap(None)

  let state: State = dict.new()

  let assert Ok(_) =
    glisten.handler(fn(_conn) { #(state, None) }, fn(msg, state, conn) {
      let assert Packet(pkt) = msg
      let assert Ok(pkt) = bit_array.to_string(pkt)

      let send = fn(string: Result(String, String)) {
        case string {
          Ok(string) -> "+" <> string <> "\r\n"
          Error("") -> "$-1\r\n"
          Error(msg) -> "-" <> msg <> "\r\n"
        }
        |> bytes_builder.from_string
        |> glisten.send(conn, _)
      }

      let send_bulk = fn(string: Result(String, String)) {
        case string {
          Ok(string) -> bulk_string(string)
          Error(msg) -> "-" <> msg <> "\r\n"
        }
        |> bytes_builder.from_string
        |> glisten.send(conn, _)
      }

      let assert [cmd, ..args] = parse(pkt)

      let state = case string.lowercase(cmd) {
        "ping" -> {
          let assert Ok(_) = send(Ok("PONG"))
          state
        }
        "echo" -> {
          let assert Ok(_) = send(Ok(string.join(args, " ")))
          state
        }
        "get" -> {
          let assert [key, ..] = args

          let assert Ok(#(value, expiry)) = dict.get(state, key)

          let assert Ok(_) = case expiry {
            Some(expiry) ->
              case birl.compare(birl.now(), expiry) {
                Gt -> send(Error(""))
                _ -> send(Ok(value))
              }
            None -> send(Ok(value))
          }
          state
        }
        "set" -> {
          case args {
            [key, value, px, expiry] -> {
              case string.lowercase(px) {
                "px" -> {
                  let assert Ok(expiry) = int.parse(expiry)
                  let expiry =
                    birl.add(birl.now(), duration.milli_seconds(expiry))

                  let state = dict.insert(state, key, #(value, Some(expiry)))
                  let assert Ok(_) = send(Ok("OK"))
                  state
                }
                _ -> {
                  let assert Ok(_) =
                    send(Error("unknown argument '" <> px <> "'"))
                  state
                }
              }
            }
            [key, value] -> {
              let state = dict.insert(state, key, #(value, None))
              let assert Ok(_) = send(Ok("OK"))

              state
            }
            _ -> {
              let assert Ok(_) =
                send(Error("unknown args" <> string.join(args, " ") <> "'"))
              state
            }
          }
        }
        "info" -> {
          let assert Ok(_) =
            send_bulk(Ok(
              "role:"
              <> replicaof
              |> option.map(fn(_) { "slave" })
              |> option.unwrap("master")
              <> "\n"
              <> "master_replid:"
              <> replication_id
              <> "\n"
              <> "master_repl_offset:"
              <> offset
              |> int.to_string(),
            ))
          state
        }
        _ -> {
          let assert Ok(_) = send(Error("unknown command '" <> cmd <> "'"))
          state
        }
      }
      actor.continue(state)
    })
    |> glisten.serve(port)

  process.sleep_forever()
}

fn parse(str) {
  case string.split(str, "\r\n") {
    [_, _, str, ""] -> [str]
    [_, _, ..more] -> take_every_2(more)
    _ -> todo as string.inspect(str)
  }
}

fn take_every_2(xs) {
  case xs {
    [] -> []
    [a] -> [a]
    [a, _, ..more] -> [a, ..take_every_2(more)]
  }
}

fn bulk_string(str) {
  "$" <> int.to_string(string.length(str)) <> "\r\n" <> str <> "\r\n"
}
