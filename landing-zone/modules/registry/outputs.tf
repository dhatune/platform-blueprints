output "repository_urls" {
  description = "Map of repository id to the host path images are pushed and pulled from."
  value = merge(
    {
      for k, r in google_artifact_registry_repository.standard :
      k => "${r.location}-docker.pkg.dev/${r.project}/${r.repository_id}"
    },
    {
      for k, r in google_artifact_registry_repository.remote :
      k => "${r.location}-docker.pkg.dev/${r.project}/${r.repository_id}"
    },
  )
}
