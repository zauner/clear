class Clear::Expression::Node::InSelect < Clear::Expression::Node
  def initialize(@target : Node, @select : Clear::SQL::SelectQuery); end

  def resolve
    "#{@target.resolve} IN ( #{@select.to_sql} )"
  end
end