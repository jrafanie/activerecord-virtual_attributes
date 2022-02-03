module ActiveRecord
  module VirtualAttributes
    # VirtualArel associates arel with an attribute
    #
    # Model.virtual_attribute :field, :string, :arel => ->(t) { t.grouping(t[:field2]) } }
    # Model.select(:field)
    #
    # is equivalent to:
    #
    # Model.select(Model.arel_table.grouping(Model.arel_table[:field2]).as(:field))
    # Model.attribute_supported_by_sql?(:field) # => true

    # in essence, this is our Arel::Nodes::VirtualAttribute
    class Arel::Nodes::Grouping
      attr_accessor :name
    end

    module VirtualArel
      # This arel table proxy is our shim to get our functionality into rails
      class ArelTableProxy < Arel::Table
        attr_accessor :klass

        # overrides Arel::Table#[]
        # adds aliases and virtual attribute arel (aka sql)
        #
        # @returns Arel::Attributes::Attribute|Arel::Nodes::Grouping|Nil
        # for regular database columns:
        #     returns an Arel::Attribute (just like Arel::Table#[])
        # for virtual attributes:
        #     returns the arel for the value
        # for non sql friendly virtual attributes:
        #     returns nil
        def [](name, table = self)
          if (col_alias = @klass.attribute_alias(name))
            name = col_alias
          end
          if @klass.virtual_attribute?(name)
            @klass.arel_for_virtual_attribute(name, table)
          else
            super
          end
        end
      end

      extend ActiveSupport::Concern

      included do
        class_attribute :_virtual_arel, :instance_accessor => false
        self._virtual_arel = {}
      end

      module ClassMethods
        if ActiveRecord.version.to_s < "6.1"
          # ActiveRecord::Core 6.0 (every version of active record seems to do this differently)
          def arel_table
            @arel_table ||= ArelTableProxy.new(table_name, :type_caster => type_caster).tap { |t| t.klass = self }
          end
        else
          # ActiveRecord::Core 6.1
          def arel_table
            @arel_table ||= ArelTableProxy.new(table_name, :klass => self)
          end
        end

        # supported by sql if any are true:
        # - it is an attribute alias
        # - it is an attribute that is non virtual
        # - it is an attribute that is virtual and has arel defined
        def attribute_supported_by_sql?(name)
          load_schema
          try(:attribute_alias?, name) ||
            (has_attribute?(name) && (!virtual_attribute?(name) || !!_virtual_arel[name.to_s]))
        end

        # private api
        #
        # @return [Nil|Arel::Nodes::Grouping]
        #   for virtual attributes:
        #       returns the arel for the column
        #   for non sql friendly virtual attributes:
        #       returns nil
        def arel_for_virtual_attribute(column_name, table) # :nodoc:
          arel_lambda = _virtual_arel[column_name.to_s]
          return unless arel_lambda

          arel = arel_lambda.call(table)
          arel = Arel::Nodes::Grouping.new(arel) unless arel.kind_of?(Arel::Nodes::Grouping)
          arel.name = column_name
          arel
        end

        private

        def define_virtual_arel(name, arel) # :nodoc:
          self._virtual_arel = _virtual_arel.merge(name => arel)
        end
      end
    end
  end
end
