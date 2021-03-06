class Neo4j::Node
  # The wrapping process is what transforms a raw CypherNode or EmbeddedNode from Neo4j::Core into a healthy ActiveNode (or ActiveRel) object.
  module Wrapper
    # this is a plugin in the neo4j-core so that the Ruby wrapper will be wrapped around the Neo4j::Node objects
    def wrapper
      self.props.symbolize_keys!
      most_concrete_class = sorted_wrapper_classes
      return self unless most_concrete_class
      wrapped_node = most_concrete_class.new
      wrapped_node.init_on_load(self, self.props)
      wrapped_node
    end

    CHECKED_LABELS_SET = Set.new

    def check_label(label_name)
      return if CHECKED_LABELS_SET.include?(label_name)

      load_class_from_label(label_name)
      # do this only once
      CHECKED_LABELS_SET.add(label_name)
    end

    # Makes the determination of whether to use <tt>_classname</tt> (or whatever is defined by config) or the node's labels.
    def sorted_wrapper_classes
      if self.props.is_a?(Hash) && self.props.key?(Neo4j::Config.class_name_property)
        self.props[Neo4j::Config.class_name_property].constantize
      else
        wrappers = _class_wrappers
        return self if wrappers.nil?
        wrapper_classes = wrappers.map { |w| Neo4j::ActiveNode::Labels._wrapped_labels[w] }
        wrapper_classes.sort.first
      end
    end

    def load_class_from_label(label_name)
      label_name.to_s.split('::').inject(Kernel) { |container, name| container.const_get(name.to_s) }
    rescue NameError
      nil
    end

    def _class_wrappers
      labels.find_all do |label_name|
        check_label(label_name)
        Neo4j::ActiveNode::Labels._wrapped_labels[label_name].class == Class
      end
    end
  end
end
