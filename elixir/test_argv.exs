defmodule TestArgv do
  def run do
    IO.inspect(System.argv())
  end
end
TestArgv.run()
