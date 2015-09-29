require "helper"

module Neovim
  RSpec.describe AsyncSession do
    it "receives requests" do
      server = TCPServer.new("0.0.0.0", 3333)
      event_loop = EventLoop.tcp("0.0.0.0", 3333)
      stream = MsgpackStream.new(event_loop)
      async = AsyncSession.new(stream)
      messages = []

      srv_thr = Thread.new do
        client = server.accept
        client.write(MessagePack.pack(
          [0, 123, "func", [1, 2, 3]]
        ))

        client.close
        server.close
      end

      req_cb = Proc.new do |*payload|
        messages << payload
        async.shutdown
      end

      async.run(req_cb)
      srv_thr.join

      expect(messages.first.size).to eq(3)
      expect(messages.first[0..1]).to eq(["func", [1, 2, 3]])
      expect(messages.first[2]).to be_a(AsyncSession::Responder)
    end

    it "receives notifications" do
      server = TCPServer.new("0.0.0.0", 3333)
      event_loop = EventLoop.tcp("0.0.0.0", 3333)
      stream = MsgpackStream.new(event_loop)
      async = AsyncSession.new(stream)
      messages = []

      srv_thr = Thread.new do
        client = server.accept
        client.write(MessagePack.pack(
          [2, "func", [1, 2, 3]]
        ))

        client.close
        server.close
      end

      not_cb = Proc.new do |*payload|
        messages << payload
        async.shutdown
      end

      async.run(nil, not_cb)
      srv_thr.join

      expect(messages).to eq([["func", [1, 2, 3]]])
    end

    it "receives responses to requests" do
      server = TCPServer.new("0.0.0.0", 3333)
      event_loop = EventLoop.tcp("0.0.0.0", 3333)
      stream = MsgpackStream.new(event_loop)
      async = AsyncSession.new(stream)
      messages = []

      srv_thr = Thread.new do
        client = server.accept
        messages << client.readpartial(1024)

        client.write(MessagePack.pack(
          [1, 0, [0, "error"], "result"]
        ))

        client.close
        server.close
      end

      async.request("func", 1, 2, 3) do |error, result|
        expect(error).to eq("error")
        expect(result).to eq("result")
        async.shutdown
      end

      async.run
      srv_thr.join

      expect(messages).to eq(
        [MessagePack.pack([0, 0, "func", [1, 2, 3]])]
      )
    end
  end
end
