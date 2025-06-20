#include <linux/version.h>

#if LINUX_VERSION_CODE >= KERNEL_VERSION(6,8,0)
static int xgbe_get_rxfh(struct net_device *netdev,
                         struct ethtool_rxfh_param *rxfh)
{
	struct xgbe_prv_data *pdata = netdev_priv(netdev);
	unsigned int i;

	if (rxfh->indir) {
		for (i = 0; i < ARRAY_SIZE(pdata->rss_table); i++)
			rxfh->indir[i] = XGMAC_GET_BITS(pdata->rss_table[i],
							  MAC_RSSDR, DMCH);
	}

	if (rxfh->key)
		memcpy(rxfh->key, pdata->rss_key, sizeof(pdata->rss_key));

	rxfh->hfunc = ETH_RSS_HASH_TOP;

	return 0;
}

static int xgbe_set_rxfh(struct net_device *netdev,
                         struct ethtool_rxfh_param *rxfh,
                         struct netlink_ext_ack *extack)
{
	struct xgbe_prv_data *pdata = netdev_priv(netdev);
	struct xgbe_hw_if *hw_if = &pdata->hw_if;
	unsigned int ret;

	if (rxfh->hfunc \!= ETH_RSS_HASH_NO_CHANGE && rxfh->hfunc \!= ETH_RSS_HASH_TOP) {
		netdev_err(netdev, "unsupported hash function\n");
		return -EOPNOTSUPP;
	}

	if (rxfh->indir) {
		ret = hw_if->set_rss_lookup_table(pdata, rxfh->indir);
		if (ret)
			return ret;
	}

	if (rxfh->key) {
		ret = hw_if->set_rss_hash_key(pdata, rxfh->key);
		if (ret)
			return ret;
	}

	return 0;
}
#else
static int xgbe_get_rxfh(struct net_device *netdev, u32 *indir, u8 *key,
                         u8 *hfunc)
{
	struct xgbe_prv_data *pdata = netdev_priv(netdev);
	unsigned int i;

	if (indir) {
		for (i = 0; i < ARRAY_SIZE(pdata->rss_table); i++)
			indir[i] = XGMAC_GET_BITS(pdata->rss_table[i],
						  MAC_RSSDR, DMCH);
	}

	if (key)
		memcpy(key, pdata->rss_key, sizeof(pdata->rss_key));

	if (hfunc)
		*hfunc = ETH_RSS_HASH_TOP;

	return 0;
}

static int xgbe_set_rxfh(struct net_device *netdev, const u32 *indir,
                         const u8 *key, const u8 hfunc)
{
	struct xgbe_prv_data *pdata = netdev_priv(netdev);
	struct xgbe_hw_if *hw_if = &pdata->hw_if;
	unsigned int ret;

	if (hfunc \!= ETH_RSS_HASH_NO_CHANGE && hfunc \!= ETH_RSS_HASH_TOP) {
		netdev_err(netdev, "unsupported hash function\n");
		return -EOPNOTSUPP;
	}

	if (indir) {
		ret = hw_if->set_rss_lookup_table(pdata, indir);
		if (ret)
			return ret;
	}

	if (key) {
		ret = hw_if->set_rss_hash_key(pdata, key);
		if (ret)
			return ret;
	}

	return 0;
}
#endif
