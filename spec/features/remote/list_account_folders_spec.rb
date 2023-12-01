require "features/helper"

RSpec.describe "imap-backup remote folders", :container, type: :aruba do
  let(:account) { test_server_connection_parameters }
  let(:config_options) { {accounts: [account]} }
  let(:command) { "imap-backup remote folders #{account[:username]}" }

  before do
    create_config(**config_options)
  end

  it "lists folders" do
    run_command_and_stop command

    expect(last_command_started).to have_output(/"INBOX"/)
  end

  context "when JSON is requested" do
    let(:command) { "imap-backup remote folders #{account[:username]} --format json" }

    it "lists folders as JSON" do
      run_command_and_stop command

      expect(last_command_started).to have_output(/\{"name":"INBOX"\}/)
    end
  end

  context "when a config path is supplied" do
    let(:custom_config_path) { File.join(File.expand_path("~/.imap-backup"), "foo.json") }
    let(:config_options) do
      {path: custom_config_path, accounts: [other_server_connection_parameters]}
    end
    let(:account) { other_server_connection_parameters }
    let(:command) do
      "imap-backup remote folders #{account[:username]} --config #{custom_config_path}"
    end

    it "lists folders" do
      run_command_and_stop command

      expect(last_command_started).to have_output(/"INBOX"/)
    end
  end
end
