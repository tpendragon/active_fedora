require "blacklight"
# Hydra libraries
module Hydra
  extend Blacklight::Configurable
  extend ActiveSupport::Autoload
  ## Matz says that autoload is going away, so we ought to discontinue this.
  autoload :Configurable, 'blacklight/configurable'
  autoload :Assets
  autoload :FileAssets
  autoload :AccessControlsEvaluation
  autoload :AccessControlsEnforcement
end


require 'mediashelf/active_fedora_helper'

require 'hydra/repository_controller'
require 'hydra/assets_controller_helper'
require 'hydra/file_assets_helper'

require 'hydra/rights_metadata'
require 'hydra/common_mods_index_methods'
require 'hydra/mods_article'
require 'hydra/model_methods'
require 'hydra/models/file_asset'

Dir[File.join(File.dirname(__FILE__), "hydra", "*.rb")].each {|f| require f}