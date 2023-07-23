require "features/helper"

RSpec.describe "imap-backup restore", type: :aruba, docker: true do
  include_context "message-fixtures"

  let(:account_config) do
    test_server_connection_parameters.merge(folders: [{name: folder}])
  end
  let(:folder) { "my-stuff" }
  let(:messages_as_mbox) do
    to_mbox_entry(**msg1) + to_mbox_entry(**msg2)
  end
  let(:messages_as_server_messages) do
    [message_as_server_message(**msg1), message_as_server_message(**msg2)]
  end
  let(:uid_validity) { 1234 }
  let(:email) { test_server_connection_parameters[:username] }
  let(:config_options) { {accounts: [account_config]} }

  let!(:pre) {}
  let!(:setup) do
    create_config(**config_options)
    create_local_folder email: email, folder: folder, uid_validity: uid_validity
    append_local email: email, folder: folder, flags: [:Flagged], **msg1
    append_local(
      email: email, folder: folder, flags: [:Draft, :$NON_SYSTEM_FLAG], **msg2
    )

    run_command_and_stop("imap-backup restore #{email}")
  end
  let(:cleanup) do
    test_server.delete_folder folder
    test_server.disconnect
  end

  after { cleanup }

  context "when the folder doesn't exist" do
    it "restores messages" do
      messages = test_server.folder_messages(folder).map { |m| server_message_to_body(m) }
      expect(messages).to eq(messages_as_server_messages)
    end

    it "restores flags" do
      messages = test_server.folder_messages(folder)
      flags = messages.map { |m| m["FLAGS"] }

      expect(flags[0]).to include(:Flagged)
    end

    it "updates local uids to match the new server ones" do
      updated_imap_content = imap_parsed(email, folder)
      stored_uids = updated_imap_content[:messages].map { |m| m[:uid] }
      expect(test_server.folder_uids(folder)).to eq(stored_uids)
    end

    it "sets the backup uid_validity to match the new folder" do
      updated_imap_content = imap_parsed(email, folder)
      expect(updated_imap_content[:uid_validity]).
        to eq(test_server.folder_uid_validity(folder))
    end
  end

  context "when the folder exists" do
    let(:email3) { test_server.send_email folder, **msg3 }

    context "when the uid_validity matches" do
      let(:pre) do
        test_server.create_folder folder
        email3
        uid_validity
      end
      let(:messages_as_server_messages) do
        [
          message_as_server_message(**msg3),
          message_as_server_message(**msg1),
          message_as_server_message(**msg2)
        ]
      end
      let(:uid_validity) { test_server.folder_uid_validity(folder) }

      it "appends to the existing folder" do
        messages = test_server.folder_messages(folder).map { |m| server_message_to_body(m) }
        expect(messages).to eq(messages_as_server_messages)
      end
    end

    context "when the uid_validity doesn't match" do
      context "when the folder is empty" do
        let(:pre) do
          test_server.create_folder folder
        end

        it "sets the backup uid_validity to match the folder" do
          updated_imap_content = imap_parsed(email, folder)
          expect(updated_imap_content[:uid_validity]).
            to eq(test_server.folder_uid_validity(folder))
        end

        it "uploads to the new folder" do
          messages = test_server.folder_messages(folder).map do |m|
            server_message_to_body(m)
          end
          expect(messages).to eq(messages_as_server_messages)
        end
      end

      context "when the folder has content" do
        let(:new_folder) { "#{folder}-#{uid_validity}" }
        let(:pre) do
          test_server.create_folder folder
          email3
        end
        let(:cleanup) do
          test_server.delete_folder new_folder
          super()
        end

        it "renames the backup" do
          expect(mbox_content(email, new_folder)).to eq(messages_as_mbox)
        end

        it "leaves the existing folder as is" do
          messages = test_server.folder_messages(folder).map do |m|
            server_message_to_body(m)
          end
          expect(messages).to eq([message_as_server_message(**msg3)])
        end

        it "creates the new folder" do
          expect(test_server.folders.map(&:name)).to include(new_folder)
        end

        it "sets the backup uid_validity to match the new folder" do
          updated_imap_content = imap_parsed(email, new_folder)
          expect(updated_imap_content[:uid_validity]).
            to eq(test_server.folder_uid_validity(new_folder))
        end

        it "uploads to the new folder" do
          messages = test_server.folder_messages(new_folder).map do |m|
            server_message_to_body(m)
          end
          expect(messages).to eq(messages_as_server_messages)
        end
      end
    end
  end

  context "when non-Unicode encodings are used" do
    let(:uid_validity) { test_server.folder_uid_validity(folder) }

    let(:setup) do
      test_server.create_folder folder
      uid_validity
      create_config accounts: [account_config]
      create_local_folder email: email, folder: folder, uid_validity: uid_validity
      append_local email: email, folder: folder, **msg_iso8859

      run_command_and_stop("imap-backup restore #{email}")
    end

    it "maintains encodings" do
      message =
        test_server.folder_messages(folder).
        first["BODY[]"]

      server_message = message_as_server_message(**msg_iso8859)

      expect(message).to eq(server_message)
    end
  end

  context "when a config path is supplied" do
    let(:custom_config_path) { File.join(File.expand_path("~/.imap-backup"), "foo.json") }
    let(:config_options) { super().merge(path: custom_config_path) }

    let(:setup) do
      create_config(**config_options)
      create_local_folder(
        configuration_path: custom_config_path,
        email: email,
        folder: folder,
        uid_validity: uid_validity
      )
      append_local(
        configuration_path: custom_config_path,
        email: email,
        folder: folder,
        flags: [:Flagged],
        **msg1
      )
    end

    it "does not raise any errors" do
      run_command_and_stop(
        "imap-backup restore #{email} --config #{custom_config_path}"
      )

      expect(last_command_started).to have_exit_status(0)
    end
  end
end
