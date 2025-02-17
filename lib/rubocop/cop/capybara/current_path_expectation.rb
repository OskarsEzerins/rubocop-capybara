# frozen_string_literal: true

module RuboCop
  module Cop
    module Capybara
      # Checks that no expectations are set on Capybara's `current_path`.
      #
      # The
      # https://www.rubydoc.info/github/teamcapybara/capybara/master/Capybara/RSpecMatchers#have_current_path-instance_method[`have_current_path` matcher]
      # should be used on `page` to set expectations on Capybara's
      # current path, since it uses
      # https://github.com/teamcapybara/capybara/blob/master/README.md#asynchronous-javascript-ajax-and-friends[Capybara's waiting functionality]
      # which ensures that preceding actions (like `click_link`) have
      # completed.
      #
      # This cop does not support autocorrection in some cases.
      #
      # @example
      #   # bad
      #   expect(current_path).to eq('/callback')
      #
      #   # good
      #   expect(page).to have_current_path('/callback')
      #
      #   # bad (does not support autocorrection)
      #   expect(page.current_path).to match(variable)
      #
      #   # good
      #   expect(page).to have_current_path('/callback')
      #
      class CurrentPathExpectation < ::RuboCop::Cop::Base
        extend AutoCorrector

        MSG = 'Do not set an RSpec expectation on `current_path` in ' \
              'Capybara feature specs - instead, use the ' \
              '`have_current_path` matcher on `page`'

        RESTRICT_ON_SEND = %i[expect].freeze

        # @!method expectation_set_on_current_path(node)
        def_node_matcher :expectation_set_on_current_path, <<-PATTERN
          (send nil? :expect (send {(send nil? :page) nil?} :current_path))
        PATTERN

        # Supported matchers: eq(...) / match(/regexp/) / match('regexp')
        # @!method as_is_matcher(node)
        def_node_matcher :as_is_matcher, <<-PATTERN
          (send
            #expectation_set_on_current_path ${:to :to_not :not_to}
            ${(send nil? :eq ...) (send nil? :match (regexp ...))})
        PATTERN

        # @!method regexp_node_matcher(node)
        def_node_matcher :regexp_node_matcher, <<-PATTERN
          (send
            #expectation_set_on_current_path ${:to :to_not :not_to}
            $(send nil? :match ${str dstr xstr}))
        PATTERN

        def self.autocorrect_incompatible_with
          [Style::TrailingCommaInArguments]
        end

        def on_send(node)
          expectation_set_on_current_path(node) do
            add_offense(node.loc.selector) do |corrector|
              next unless node.chained?

              autocorrect(corrector, node)
            end
          end
        end

        private

        def autocorrect(corrector, node)
          as_is_matcher(node.parent) do |to_sym, matcher_node|
            rewrite_expectation(corrector, node, to_sym, matcher_node)
          end

          regexp_node_matcher(node.parent) do |to_sym, matcher_node, regexp|
            rewrite_expectation(corrector, node, to_sym, matcher_node)
            convert_regexp_node_to_literal(corrector, matcher_node, regexp)
          end
        end

        def rewrite_expectation(corrector, node, to_symbol, matcher_node)
          current_path_node = node.first_argument
          corrector.replace(current_path_node, 'page')
          corrector.replace(node.parent.loc.selector, 'to')
          matcher_method = if to_symbol == :to
                             'have_current_path'
                           else
                             'have_no_current_path'
                           end
          corrector.replace(matcher_node.loc.selector, matcher_method)
          add_ignore_query_options(corrector, node)
        end

        def convert_regexp_node_to_literal(corrector, matcher_node, regexp_node)
          str_node = matcher_node.first_argument
          regexp_expr = regexp_node_to_regexp_expr(regexp_node)
          corrector.replace(str_node, regexp_expr)
        end

        def regexp_node_to_regexp_expr(regexp_node)
          if regexp_node.xstr_type?
            "/\#{`#{regexp_node.value.value}`}/"
          else
            Regexp.new(regexp_node.value).inspect
          end
        end

        # `have_current_path` with no options will include the querystring
        # while `page.current_path` does not.
        # This ensures the option `ignore_query: true` is added
        # except when the expectation is a regexp or string
        def add_ignore_query_options(corrector, node)
          expectation_node = node.parent.last_argument
          expectation_last_child = expectation_node.children.last
          return if %i[
            regexp str dstr xstr
          ].include?(expectation_last_child.type)

          corrector.insert_after(
            expectation_last_child,
            ', ignore_query: true'
          )
        end
      end
    end
  end
end
