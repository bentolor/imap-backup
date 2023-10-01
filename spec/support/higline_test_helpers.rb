require "highline"

require "imap/backup/setup"

module HighLineTestHelpers
  def prepare_highline
    @input = instance_double(IO, eof?: false, gets: "q\n")
    @output = StringIO.new
    Imap::Backup::Setup.highline = HighLine.new(@input, @output)
    [@input, @output]
  end
end
