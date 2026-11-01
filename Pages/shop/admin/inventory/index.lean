import LeanWebStudy.Page
import LeanWebStudy.ShopAdmin

def main : IO Unit :=
  LeanWebStudy.Page.run fun context =>
    pure (LeanWebStudy.ShopAdmin.render context)
