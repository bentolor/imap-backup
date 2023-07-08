require "imap/backup/client/apple_mail"
require "imap/backup/client/default"
require "imap/backup/account/connection/backup_folders"
require "imap/backup/account/connection/client_factory"
require "imap/backup/account/connection/folder_names"
require "imap/backup/flag_refresher"
require "imap/backup/local_only_message_deleter"
require "imap/backup/serializer/directory"

module Imap::Backup
  class Account; end

  class Account::Connection
    attr_reader :account

    def initialize(account)
      @account = account
      @backup_folders = nil
      @client = nil
      @folder_names = nil
    end

    def folder_names
      @folder_names ||= Account::Connection::FolderNames.new(client: client).run
    end

    def backup_folders
      @backup_folders ||=
        Account::Connection::BackupFolders.new(client: client, account: account).run
    end

    def namespaces
      client.namespace
    end

    def run_backup(refresh: false)
      Logger.logger.info "Running backup of account: #{account.username}"
      # start the connection so we get logging messages in the right order
      client
      ensure_account_folder
      if account.mirror_mode
        # Delete serialized folders that are not to be backed up
        wanted = backup_folders.map(&:name)
        local_folders do |serializer, _folder|
          serializer.delete if !wanted.include?(serializer.folder)
        end
      end
      each_folder do |folder, serializer|
        begin
          next if !folder.exist?
        rescue Encoding::UndefinedConversionError
          message = "Skipping backup for '#{folder.name}' " \
                    "as it is not UTF-7 encoded correctly"
          Logger.logger.info message
          next
        end

        Logger.logger.debug "[#{folder.name}] running backup"
        serializer.apply_uid_validity(folder.uid_validity)
        Downloader.new(
          folder,
          serializer,
          multi_fetch_size: account.multi_fetch_size,
          reset_seen_flags_after_fetch: account.reset_seen_flags_after_fetch
        ).run
        if account.mirror_mode
          Logger.logger.info "Mirror mode - Deleting messages only present locally"
          LocalOnlyMessageDeleter.new(folder, serializer).run
        end
        FlagRefresher.new(folder, serializer).run if account.mirror_mode || refresh
      end
    end

    def local_folders
      return enum_for(:local_folders) if !block_given?

      ensure_account_folder
      glob = File.join(account.local_path, "**", "*.imap")
      base = Pathname.new(account.local_path)
      Pathname.glob(glob) do |path|
        name = path.relative_path_from(base).to_s[0..-6]
        serializer = Serializer.new(account.local_path, name)
        folder = Account::Folder.new(client, name)
        yield serializer, folder
      end
    end

    def restore
      local_folders do |serializer, folder|
        Uploader.new(folder, serializer).run
      end
    end

    def client
      @client ||= Account::Connection::ClientFactory.new(account: account).run
    end

    private

    def each_folder
      backup_folders.each do |folder|
        serializer = Serializer.new(account.local_path, folder.name)
        yield folder, serializer
      end
    end

    def ensure_account_folder
      raise "The backup path for #{account.username} is not set" if !account.local_path

      Utils.make_folder(
        File.dirname(account.local_path),
        File.basename(account.local_path),
        Serializer::Directory::DIRECTORY_PERMISSIONS
      )
    end
  end
end
