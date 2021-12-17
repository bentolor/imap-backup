require "thunderbird/subdirectory_placeholder"

class Thunderbird::Subdirectory
  # `path` is the UI path, it doesn't have the '.sbd' extensions
  # that are present in the real, file system path
  attr_reader :path
  attr_reader :profile

  def initialize(profile, path)
    @profile = profile
    @path = path
  end

  def set_up
    if !sub_directory?
      raise "Cannot create a subdirectory without a path"
    end

    if sub_sub_directory?
      parent_ok = parent.set_up
      return false if !parent_ok
    end

    ok = check
    return false if !ok

    FileUtils.mkdir_p full_path
    placeholder.touch

    true
  end

  # subdirectory relative path is 'Foo.sbd/Bar.sbd/Baz.sbd'
  def full_path
    relative_path = File.join(subdirectories)
    File.join(profile.local_folders_path, relative_path)
  end

  private

  def sub_directory?
    path_elements.any?
  end

  def sub_sub_directory?
    path_elements.count > 1
  end

  def parent
    if sub_sub_directory?
      self.class.new(profile, File.join(path_elements[0..-2]))
    end
  end

  # placeholder relative path is 'Foo.sbd/Bar.sbd/Baz'
  def placeholder
    @placeholder = begin
      relative_path = File.join(subdirectories[0..-2], path_elements[-1])
      path = File.join(profile.local_folders_path, relative_path)
      Thunderbird::SubdirectoryPlaceholder.new(path)
    end
  end

  def path_elements
    path.split(File::SEPARATOR)
  end

  def exists?
    File.exists?(full_path)
  end

  def is_directory?
    File.directory?(full_path)
  end

  def subdirectories
    path_elements.map { |p| "#{p}.sbd" }
  end

  def check
    case
    when placeholder.exists? && !exists?
      Kernel.puts "Can't set up folder '#{folder_path}': '#{placeholder.path}' exists, but '#{full_path}' is missing"
      false
    when exists? && !placeholder.exists?
      Kernel.puts "Can't set up folder '#{folder_path}': '#{full_path}' exists, but '#{placeholder.path}' is missing"
      false
    when placeholder.exists? && !placeholder.is_regular?
      Kernel.puts "Can't set up folder '#{folder_path}': '#{placeholder.path}' exists, but it is not a regular file"
      false
    when exists? && !is_directory?
      Kernel.puts "Can't set up folder '#{folder_path}': '#{full_path}' exists, but it is not a directory"
      false
    else
      true
    end
  end
end
