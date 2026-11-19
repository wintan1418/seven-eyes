module MediaAssetsHelper
  # What deleting a library picture does — said plainly before it happens.
  def media_delete_confirm(asset, services)
    if services.to_i.positive?
      "“#{asset.title}” is used in #{pluralize(services, "service")}. Those services keep showing it — it only " \
        "leaves My Media (and any service templates). Delete it from My Media?"
    else
      "Delete “#{asset.title}” from My Media? This can't be undone."
    end
  end
end
