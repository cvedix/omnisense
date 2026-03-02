ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(CVR.Repo, :manual)

Mimic.copy(ExOnvif.Discovery)
Mimic.copy(ExOnvif.Device)
Faker.start()
