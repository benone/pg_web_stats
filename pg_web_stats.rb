class PgWebStats
  attr_accessor :config, :connection

  def initialize(config_path)
    self.config = YAML.load_file(config_path)
    self.connection = PG.connect(
      dbname: config['database'],
      host: config['host'],
      user: config['user'],
      password: config['password'],
      port: config['port']
    )

    # create_extension
  end

  def get_stats(params)
    query = build_stats_query(params)

    results = []
    connection.exec(query) do |result|
      result.each do |row|
        results << Row.new(row, users, databases)
      end
    end

    results
  end

  def users
    unless @users
      @users = {}
      connection.exec("select oid, rolname from pg_authid;") do |result|
        result.each do |row|
          @users[row['oid']] = row['rolname']
        end
      end
      @users
    end

    @users
  end

  def databases
    unless @databases
      @databases = {}
      connection.exec("select oid, datname from pg_database;") do |result|
        result.each do |row|
          @databases[row['oid']] = row['datname']
        end
      end
      @databases
    end

    @databases
  end

  private

  def build_stats_query(params)
    order_by = params[:order]

    query = "SELECT * FROM pg_stat_statements"

    # TODO escape values from user

    where_conditions = []

    userid = params[:userid]
    if userid && !userid.empty?
      where_conditions << "userid='#{userid}'"
    end

    dbid = params[:dbid]
    if dbid && !dbid.empty?
      where_conditions << "dbid='#{dbid}'"
    end

    query += " WHERE #{where_conditions.join(" AND ")}" if where_conditions.size > 0

    query += " ORDER BY #{order_by}"

    query
  end

  def create_extension
    connection.exec('CREATE EXTENSION pg_stat_statements')
  end
end

class PgWebStats::Row
  attr_accessor :data, :users, :databases

  def initialize(data, users, databases)
    self.data = data
    self.users = users
    self.databases = databases
  end

  def respond_to?(method_sym, include_private = false)
    if data[method_sym.to_s]
      true
    else
      super
    end
  end

  def method_missing(method_sym, *arguments, &block)
    if result = data[method_sym.to_s]
      result
    else
      super
    end
  end

  def user
    users[userid]
  end

  def db
    databases[dbid]
  end

  def waste?
    clean_query = self.query.dup.downcase.strip
    keywords = ['show', 'set', 'rollback', 'savepoint', 'release', 'begin', 'create_extension']
    keywords.any? { |k| clean_query.start_with?(k) }
  end
end
