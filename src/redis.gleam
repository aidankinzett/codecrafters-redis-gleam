import gleam/bit_array
import gleam/bytes_builder
import gleam/dict.{type Dict}
import gleam/erlang/process
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{None}
import gleam/otp/actor
import gleam/result
import gleam/string
import glisten.{Packet}

pub fn main() {
  io.println("Logs from your program will appear here!")

  let assert Ok(_) =
    glisten.handler(fn(_conn) { #(dict.new(), None) }, fn(msg, state, conn) {
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
          let assert Ok(_) =
            list.at(args, 0)
            |> result.unwrap("")
            |> dict.get(state, _)
            |> result.replace_error("")
            |> send
          state
        }
        "set" -> {
          let assert [key, value, ..] = args
          let state = dict.insert(state, key, value)
          let assert Ok(_) = send(Ok("OK"))
          state
        }
        _ -> {
          let assert Ok(_) = send(Error("unknown command '" <> cmd <> "'"))
          state
        }
      }
      actor.continue(state)
    })
    |> glisten.serve(6379)

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

fn bulk(str) {
  "$" <> int.to_string(string.length(str)) <> "\r\n" <> str <> "\r\n"
}
