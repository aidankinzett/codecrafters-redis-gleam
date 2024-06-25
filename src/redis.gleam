import gleam/bit_array
import gleam/bytes_builder
import gleam/erlang/process
import gleam/int
import gleam/io
import gleam/option.{None}
import gleam/otp/actor
import gleam/string
import glisten.{Packet}

pub fn main() {
  io.println("Logs from your program will appear here!")

  let assert Ok(_) =
    glisten.handler(fn(_conn) { #(Nil, None) }, fn(msg, state, conn) {
      let assert Packet(pkt) = msg
      let assert Ok(pkt) = bit_array.to_string(pkt)
      let assert Ok(Nil) = case parse(pkt) {
        ["ping"] | ["PING"] ->
          "+PONG\r\n" |> bytes_builder.from_string |> glisten.send(conn, _)
        ["echo", str] | ["ECHO", str] ->
          bulk(str) |> bytes_builder.from_string |> glisten.send(conn, _)
        x -> todo as string.inspect(x)
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
