require "imap/backup/logger"

module Imap::Backup
  RSpec.shared_examples "an action that handles Logger options" do |action:, &block|
    before do
      allow(Logger).to receive(:setup_logging).and_call_original
      action.call(subject, {quiet: true, verbose: [true]})
    end

    it "configures the logger" do
      expect(Logger).to have_received(:setup_logging)
    end

    block&.call
  end
end
