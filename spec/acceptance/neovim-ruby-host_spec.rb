require "helper"
require "tmpdir"

RSpec.describe "neovim-ruby-host" do
  it "loads and runs plugins from Ruby source files" do
    Dir.mktmpdir do |pwd|
      Dir.chdir(pwd) do
        File.write("./plugin1.rb", <<-RUBY)
          Neovim.plugin do |plug|
            plug.command(:SyncAdd, :args => 2, :sync => true) do |nvim, x, y|
              x + y
            end
          end
        RUBY

        File.write("./plugin2.rb", <<-RUBY)
          Neovim.plugin do |plug|
            plug.command(:AsyncSetLine, :args => 1) do |nvim, str|
              nvim.current.line = str
            end
          end
        RUBY

        nvim = Neovim.attach_child(["--headless", "-u", "NONE", "-N", "-n"])

        host_exe = File.expand_path("../../../bin/neovim-ruby-host", __FILE__)
        nvim.command("let host = rpcstart('#{host_exe}', ['./plugin1.rb', './plugin2.rb'])")

        expect(nvim.eval("rpcrequest(host, 'poll')")).to eq("ok")
        expect(nvim.eval("rpcrequest(host, 'SyncAdd', 1, 2)")).to eq(3)

        expect {
          nvim.eval("rpcnotify(host, 'AsyncSetLine', 'foo')")
        }.to change { nvim.current.buffer.lines.to_a }.from([""]).to(["foo"])

        expect {
          nvim.eval("rpcnotify(host, 'Unkown')")
        }.not_to raise_error

        expect {
          nvim.eval("call rpcrequest(host, 'Unknown')")
        }.to raise_error(ArgumentError)
      end
    end
  end
end
