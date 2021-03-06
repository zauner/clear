module Clear::Migration
  # Helper to create or alter table.
  struct Table < Operation
    record ColumnOperation, column : String, type : String,
      null : Bool = false, default : SQL::Any = nil, primary : Bool = false

    record IndexOperation, field : String, name : String,
      using : String? = nil, unique : Bool = false

    record FkeyOperation, fields : Array(String), table : String,
      foreign_fields : Array(String), on_delete : String, primary : Bool

    getter name : String
    getter? is_create : Bool

    getter column_operations : Array(ColumnOperation) = [] of ColumnOperation
    getter index_operations : Array(IndexOperation) = [] of IndexOperation
    getter fkey_operations : Array(FkeyOperation) = [] of FkeyOperation

    def initialize(@name, @is_create)
      raise "Not yet implemented" unless is_create?
    end

    # Add the timestamps to the field.
    def timestamps(null = false)
      add_column(:created_at, "timestamp without time zone", null: null, default: "NOW()")
      add_column(:updated_at, "timestamp without time zone", null: null, default: "NOW()")
      add_index(:created_at)
      add_index(:updated_at)
    end

    def references(to, name : String? = nil, on_delete = "restrict", type = "bigint",
                   null = false, foreign_key = "id", primary = false)
      name ||= to.singularize.underscore + "_id"

      add_column(name, type, null: null, index: true)

      add_fkey(fields: [name.to_s], table: to.to_s, foreign_fields: [foreign_key.to_s],
        on_delete: on_delete.to_s, primary: primary)
    end

    def add_fkey(fields : Array(String), table : String,
                 foreign_fields : Array(String), on_delete : String, primary : Bool)
      self.fkey_operations << FkeyOperation.new(fields: fields, table: table,
        foreign_fields: foreign_fields, on_delete: on_delete, primary: primary)
    end

    # Add/alter a column for this table.
    def add_column(column, type, default = nil, null = true, primary = false, index = false, unique = false)
      self.column_operations << ColumnOperation.new(column: column.to_s, type: type.to_s,
        default: default, null: null, primary: primary)

      if unique
        add_index(field: column, unique: true)
      elsif index
        add_index(field: column, unique: false)
      end
    end

    # Add or replace an index for this table.
    # Alias for `add_index`
    def index(field, name = nil, using = nil, unique = false)
      add_index(field, name, using, unique)
    end

    private def add_index(field, name = nil, using = nil, unique = false)
      name ||= safe_index_name([@name, field.to_s].join("_"))

      using = using.to_s unless using.nil?

      self.index_operations << IndexOperation.new(
        field: field.to_s, name: name, using: using, unique: unique
      )
    end

    #
    # Return a safe index name from the condition string
    private def safe_index_name(str)
      str.underscore.gsub(/[^a-zA-Z0-9_]/, "_").gsub(/_+/, "_")
    end

    def up
      columns_and_fkeys = print_columns + print_fkeys

      content = "(#{columns_and_fkeys.join(", ")})" unless columns_and_fkeys.empty?

      [
        (["CREATE TABLE", @name, content].reject(&.nil?).join(" ") if is_create?),
      ] + print_indexes
    end

    def down
      [
        (["DROP TABLE", @name].join(" ") if is_create?),
      ]
    end

    private def print_fkeys
      # FOREIGN KEY (b, c) REFERENCES other_table (c1, c2)
      fkey_operations.map do |x|
        ["FOREIGN KEY",
         "(" + x.fields.join(", ") + ")",
         "REFERENCES",
         x.table,
         "(" + x.foreign_fields.join(", ") + ")",
         "ON DELETE",
         x.on_delete]
          .compact.join(" ")
      end
    end

    private def print_indexes
      index_operations.map do |x|
        [
          "CREATE",
          (x.unique ? "UNIQUE" : nil),
          "INDEX",
          x.name,
          "ON",
          self.name,
          (x.using ? "USING #{x.using}" : nil),
          "(#{x.field})",
        ].compact.join(" ")
      end
    end

    private def print_columns
      column_operations.map do |x|
        [x.column,
         x.type,
         x.null ? nil : "NOT NULL",
         !x.default.nil? ? "DEFAULT #{x.default}" : nil,
         x.primary ? "PRIMARY KEY" : nil]
          .compact.join(" ")
      end
    end

    #
    # Method missing is used to generate add_column using the method name as
    # column type (ActiveRecord's style)
    macro method_missing(caller)
      type = {{caller.name.stringify}}

      type = case type
      when "string"
        "text"
      when "int32", "integer"
        "integer"
      when "int64", "long"
        "bigint"
      when "datetime"
        "timestamp without time zone"
      when "datetimetz"
        "timestamp with time zone"
      else
        type
      end

      {% if caller.named_args.is_a?(Nop) %}
        self.add_column( {{caller.args[0]}}.to_s, type: type )
      {% else %}
        self.add_column( {{caller.args[0]}}.to_s, type: type, {{caller.named_args.join(", ").id}} )
      {% end %}
    end
  end

  struct AddTable < Operation
    @table : String

    def initialize(@table)
    end

    def up
      ["CREATE TABLE #{@table}"]
    end

    def down
      ["DROP TABLE #{@table}"]
    end
  end

  struct DropTable < Operation
    @table : String

    def initialize(@table)
    end

    def up
      ["DROP TABLE #{@table}"]
    end

    def down
      ["CREATE TABLE #{@table}"]
    end
  end

  module Helper
    #
    # Helper used in migration to create a new table.
    #
    # Usage:
    #
    # ```
    # create_table(:users) do |t|
    #   t.string :first_name
    #   t.string :last_name
    #   t.email :email, unique: true
    #   t.timestamps
    # end
    # ```
    #
    # By default, a column `id` of type `integer` will be created as primary key of the table.
    # This can be prevented using `primary: false`
    #
    # ```
    # create_table(:users, id: false) do |t|
    #   t.integer :user_id, primary: true # Use custom name for the primary key
    #
    #   t.string :first_name
    #   t.string :last_name
    #   t.email :email, unique: true
    #   t.timestamps
    # end
    # ```
    #
    def create_table(name, id = true, &block)
      table = Table.new(name.to_s, is_create: true)

      if id
        table.bigserial :id, primary: true
      end

      yield(table)
      self.add_operation(table)
    end
  end
end
