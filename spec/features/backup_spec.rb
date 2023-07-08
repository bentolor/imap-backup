require "features/helper"

RSpec.describe "imap-backup backup", type: :aruba, docker: true do
  include_context "message-fixtures"

  let(:backup_folders) { [{name: folder}] }
  let(:folder) { "my-stuff" }
  let(:messages_as_mbox) do
    to_mbox_entry(**msg1) + to_mbox_entry(**msg2)
  end
  let(:account) { test_server_connection_parameters }
  let(:email) { account[:username] }
  let(:config_options) { {accounts: [account]} }
  let(:write_config) { create_config(**config_options) }

  let!(:pre) do
    test_server.delete_folder folder
  end
  let(:command) { "imap-backup backup" }
  let!(:setup) do
    test_server.create_folder folder
    test_server.send_email folder, **msg1
    test_server.send_email folder, **msg2
    write_config

    run_command_and_stop command
  end

  after do
    test_server.delete_folder folder
    test_server.disconnect
  end

  it "downloads messages" do
    expect(mbox_content(email, folder)).to eq(messages_as_mbox)
  end

  describe "IMAP metadata" do
    let(:imap_metadata) { imap_parsed(email, folder) }
    let(:folder_uids) { test_server.folder_uids(folder) }

    it "saves IMAP metadata in a JSON file" do
      expect { imap_metadata }.to_not raise_error
    end

    it "saves a file version" do
      expect(imap_metadata[:version].to_s).to match(/^[0-9.]$/)
    end

    it "records IMAP ids" do
      uids = imap_metadata[:messages].map { |m| m[:uid] }

      expect(uids).to eq(folder_uids)
    end

    it "records message offsets in the mbox file" do
      offsets = imap_metadata[:messages].map { |m| m[:offset] }
      expected = [0, to_mbox_entry(**msg1).length]

      expect(offsets).to eq(expected)
    end

    it "records message lengths in the mbox file" do
      lengths = imap_metadata[:messages].map { |m| m[:length] }
      expected = [to_mbox_entry(**msg1).length, to_mbox_entry(**msg2).length]

      expect(lengths).to eq(expected)
    end

    it "records uid_validity" do
      expect(imap_metadata[:uid_validity]).to eq(test_server.folder_uid_validity(folder))
    end

    context "with the --refresh option" do
      let(:command) { "imap-backup backup --refresh" }
      let(:connection) { Imap::Backup::Account::Connection.new(Imap::Backup::Account.new(account)) }

      context "with messages that have already been backed up" do
        let!(:pre) do
          super()
          write_config
          test_server.create_folder folder
          test_server.send_email folder, **msg3, flags: [:Draft]
          connection.run_backup
          connection.client.disconnect
          test_server.set_flags folder, [1], [:Seen]
        end

        it "updates flags" do
          imap_content = imap_parsed(email, folder)
          message3 = imap_content[:messages].first
          flags = message3[:flags].reject { |f| f == "Recent" }
          expect(flags).to eq(["Seen"])
        end
      end
    end

    context "when uid_validity does not match" do
      let(:new_name) { "NEWNAME" }
      let(:original_folder_uid_validity) { test_server.folder_uid_validity(folder) }
      let(:connection) { Imap::Backup::Account::Connection.new(Imap::Backup::Account.new(account)) }
      let!(:pre) do
        super()
        test_server.delete_folder new_name
        test_server.create_folder folder
        test_server.send_email folder, **msg3
        original_folder_uid_validity
        connection.run_backup
        connection.client.disconnect
        test_server.rename_folder folder, new_name
      end
      let(:renamed_folder) { "#{folder}-#{original_folder_uid_validity}" }

      after do
        test_server.delete_folder new_name
      end

      it "renames the old backup" do
        expect(mbox_content(email, renamed_folder)).to eq(to_mbox_entry(**msg3))
      end

      it "renames the old metadata file" do
        expect(imap_parsed(email, renamed_folder)).to be_a Hash
      end

      it "downloads messages" do
        expect(mbox_content(email, folder)).to eq(messages_as_mbox)
      end

      it "creates a metadata file" do
        expect(imap_parsed(email, folder)).to be_a Hash
      end

      context "when a renamed local backup exists" do
        let!(:pre) do
          super()
          create_directory account[:local_path]
          valid_imap_data = {version: 3, uid_validity: 1, messages: []}
          imap_path = File.join(account[:local_path], "#{renamed_folder}.imap")
          File.write(imap_path, valid_imap_data.to_json)
          mbox_path = File.join(account[:local_path], "#{renamed_folder}.mbox")
          File.write(mbox_path, "existing mbox")
        end

        it "renames the renamed backup to a uniquely name" do
          renamed = "#{folder}-#{original_folder_uid_validity}-1"
          expect(mbox_content(email, renamed)).to eq(to_mbox_entry(**msg3))
        end
      end
    end
  end

  context "in mirror mode" do
    let(:account) { test_server_connection_parameters.merge(mirror_mode: true) }
    let(:imap_path) { File.join(account[:local_path], "Foo.imap") }
    let(:mbox_path) { File.join(account[:local_path], "Foo.mbox") }

    let!(:pre) do
      create_directory account[:local_path]
      message = "existing mbox"
      valid_imap_data = {
        version: 3, uid_validity: 1, messages: [{uid: 1, offset: 0, length: message.length}]
      }
      File.write(imap_path, valid_imap_data.to_json)
      File.write(mbox_path, message)
    end

    context "with folders that are not being backed up" do
      it "deletes .imap files" do
        expect(File.exist?(imap_path)).to be false
      end

      it "deletes .mbox files" do
        expect(File.exist?(mbox_path)).to be false
      end
    end
  end

  context "when a config path is supplied" do
    let(:custom_config_path) { File.join(File.expand_path("~/.imap-backup"), "foo.json") }
    let(:config_options) do
      {path: custom_config_path, accounts: [other_server_connection_parameters]}
    end
    let(:account) { other_server_connection_parameters }
    let(:command) { "imap-backup backup --config #{custom_config_path}" }

    let(:setup) do
      other_server.create_folder folder
      other_server.send_email folder, **msg1
      write_config
    end

    after do
      other_server.delete_folder folder
      other_server.disconnect
    end

    it "downloads messages" do
      run_command_and_stop command

      content = mbox_content(email, folder, configuration_path: custom_config_path)
      messages_as_mbox = to_mbox_entry(**msg1)
      expect(content).to eq(messages_as_mbox)
    end
  end
end
