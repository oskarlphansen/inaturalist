class Taxon < ActiveRecord::Base

  include ActsAsElasticModel

  # used to cache place_ids when bulk indexing
  attr_accessor :indexed_place_ids

  scope :load_for_index, -> { includes(:colors, :taxon_names, :taxon_descriptions) }
  settings index: { number_of_shards: 1, analysis: ElasticModel::ANALYSIS } do
    mappings(dynamic: true) do
      indexes :names do
        indexes :name, index_analyzer: "ascii_snowball_analyzer",
          search_analyzer: "ascii_snowball_analyzer"
        indexes :name_autocomplete, index_analyzer: "autocomplete_analyzer",
          search_analyzer: "standard_analyzer"
      end
    end
  end

  def as_indexed_json(options={})
    json = {
      id: id,
      name: name,
      names: taxon_names.sort_by(&:position).map{ |tn| tn.as_indexed_json(autocomplete: !options[:basic]) },
      rank: rank,
      rank_level: rank_level,
      iconic_taxon_id: iconic_taxon_id,
      ancestor_ids: ((ancestry ? ancestry.split("/").map(&:to_i) : [ ]) << id )
    }
    unless options[:basic]
      json.merge!({
        created_at: created_at,
        colors: colors.map(&:as_indexed_json),
        is_active: is_active,
        ancestry: ancestry,
        observations_count: observations_count,
        # see prepare_for_index. Basicaly indexed_place_ids may be set
        # when using Taxon.elasticindex! to bulk import
        place_ids: (indexed_place_ids || listed_taxa.map(&:place_id)).compact.uniq
      })
    end
    json
  end

  # This custom prepare_for_index is used to preload place_ids
  # using a SQL call to avoid loading all the listed_taxa
  # into AR objects. This saves a lot of time when bulk indexing
  def self.prepare_batch_for_index(taxa)
    # make sure we default all caches to empty arrays
    # this prevents future lookups for instances with no results
    taxa.each{ |t| t.indexed_place_ids ||= [ ] }
    taxa_by_id = Hash[ taxa.map{ |t| [ t.id, t ] } ]
    batch_ids_string = taxa_by_id.keys.join(",")
    # fetch all place_ids store them in `indexed_place_ids`
    connection.execute("
      SELECT taxon_id, place_id
      FROM listed_taxa lt
      JOIN places p ON (lt.place_id = p.id)
      WHERE lt.taxon_id IN (#{ batch_ids_string })").to_a.each do |r|
      if t = taxa_by_id[ r["taxon_id"].to_i ]
        t.indexed_place_ids << r["place_id"].to_i
      end
    end
  end

end