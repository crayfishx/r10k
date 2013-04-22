require 'forwardable'
require 'r10k/logging'
require 'r10k/execution'
require 'r10k/git/command'
require 'r10k/git/cache'

module R10K
module Git
class WorkingDir
  # Implements sparse git repositories with shared objects
  #
  # Working directory instances use the git alternatives object store, so that
  # working directories only contain checked out files and all object files are
  # shared.

  include R10K::Logging
  include R10K::Execution
  include R10K::Git::Command

  extend Forwardable

  # @!attribute [r] cache
  #   @return [R10K::Git::Cache] The object cache backing this working directory
  attr_reader :cache

  # @!attribute [r] remote
  #   @return [String] The URL to the git repository
  attr_reader :remote

  # @!attribute [r] basedir
  #   @return [String] The basedir for the working directory
  attr_reader :basedir

  # @!attribute [r] dirname
  #   @return [String] The name for the directory
  attr_reader :dirname

  # @!attribute [r] ref
  #   @return [String] The git reference to use check out in the given directory
  attr_reader :ref

  # Instantiates a new git synchro and optionally prepares for caching
  #
  # @param [String] ref
  # @param [String] remote
  # @param [String] basedir
  # @param [String] dirname
  def initialize(ref, remote, basedir, dirname = nil)
    @ref     = ref
    @remote  = remote
    @basedir = basedir
    @dirname = dirname || ref

    @full_path = File.join(@basedir, @dirname)

    @cache = R10K::Git::Cache.new(@remote)
  end

  # Synchronize the local git repository.
  def sync
    # TODO stop forcing a sync every time.
    @cache.sync

    if cloned?
      fetch
    else
      clone
    end
    reset
  end

  # Determine if repo has been cloned into a specific dir
  #
  # @return [true, false] If the repo has already been cloned
  def cloned?
    dot_git = File.join(@full_path, '.git')
    File.directory? dot_git
  end

  private

  # Perform a non-bare clone of a git repository.
  def clone
    # We do the clone against the target repo using the `--reference` flag so
    # that doing a normal `git pull` on a directory will work.
    git "clone --reference #{@cache.path} #{@remote} #{@full_path}"
    git "remote add cache #{@cache.path}", :path => @full_path
  end

  def fetch
    # XXX This is crude but it'll ensure that the right remote is used for
    # the cache.
    git "remote set-url cache #{@cache.path}", :path => @full_path
    git "fetch --prune cache", :path => @full_path
  end

  # Reset a git repo with a working directory to a specific ref
  def reset
    commit = resolve_commit(@ref)

    begin
      git "reset --hard #{commit}", :path => @full_path
    rescue R10K::ExecutionFailure => e
      logger.error "Unable to locate commit object #{commit} in git repo #{@full_path}"
      raise
    end
  end

  # Resolve a ref to a commit hash
  #
  # @param [String] ref
  #
  # @return [String] The dereferenced hash of `ref`
  def resolve_commit(ref)
    commit = git "rev-parse #{@ref}^{commit}", :git_dir => @cache.path
    commit.chomp
  rescue R10K::ExecutionFailure => e
    logger.error "Could not resolve ref #{@ref.inspect} for git cache #{@cache.path}"
    raise
  end
end
end
end