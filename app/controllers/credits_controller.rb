# Public /credits page: every translation we offer with its licence, plus the
# sources of cross-references, Strong's data and commentary, with the
# attributions their licences require (CC BY / CC BY-SA).
class CreditsController < ApplicationController
  allow_unauthenticated_access only: %i[ show ]

  def show
    @translations = Translation.available.to_a
  end
end
