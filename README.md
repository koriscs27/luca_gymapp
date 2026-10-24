# LucaGymapp

To start your Phoenix server:

* Run `mix setup` to install and setup dependencies
* Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

## Coupon codes

Configure coupon names and discounts together in the ignored `.env.dev` file for local development, or set `COUPON_CODES` as an environment variable in production. Its value is a JSON list; discounts are fractions, so `0.5` means 50% off:

```text
COUPON_CODES=[{"name":"YOUR_PRIVATE_CODE","discount":0.5},{"name":"ANOTHER_PRIVATE_CODE","discount":0.2}]
```

In `.env.dev`, leave off the surrounding quotes as shown. When setting the variable from a shell or deployment dashboard, quote the JSON as required by that environment. Coupon names are trimmed and matched without regard to letter case.

Ready to run in production? Please [check our deployment guides](https://hexdocs.pm/phoenix/deployment.html).

## Learn more

* Official website: https://www.phoenixframework.org/
* Guides: https://hexdocs.pm/phoenix/overview.html
* Docs: https://hexdocs.pm/phoenix
* Forum: https://elixirforum.com/c/phoenix-forum
* Source: https://github.com/phoenixframework/phoenix
