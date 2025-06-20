# AMD XGBE Driver Patches for ASUSTOR FlashStor on Proxmox VE 8.4

This guide documents the necessary patches to get AMD XGMAC 10GbE networking working on ASUSTOR FlashStor Gen 2 systems (FS6812X/FS6806X) running Proxmox VE 8.4 with kernel 6.8.12-11-pve.

## Background

The ASUSTOR FlashStor systems use AMD XGMAC controllers for 10GbE networking, but the stock Linux drivers have issues with:
1. Kernel 6.8 API changes breaking compilation
2. PHY detection failures causing fallback to incorrect modes
3. Auto-negotiation problems with 10GBASE-T copper connections

## Hardware Details

- **System**: ASUSTOR FlashStor FS6812X/FS6806X
- **NIC**: AMD XGMAC 10GbE controller
- **Connection**: 10GBASE-T (copper RJ45)
- **Kernel**: 6.8.12-11-pve (Proxmox VE 8.4)

## Required Patches

### 1. Kernel 6.8 Compatibility (xgbe-ethtool.c)

The ethtool RSS API changed in kernel 6.8, requiring conditional compilation:

```c
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
    
    if (rxfh->hfunc && (rxfh->hfunc != ETH_RSS_HASH_TOP))
        return -EOPNOTSUPP;
        
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
// Keep original pre-6.8 functions for older kernels
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
    
    if (hfunc && (hfunc != ETH_RSS_HASH_TOP))
        return -EOPNOTSUPP;
        
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
```

### 2. PHY Detection Bypass (xgbe-phy-v2.c)

The driver fails to detect external PHY for 10GBASE-T, so we bypass this:

```c
// Around line 1155, in xgbe_phy_find_phy_device()
/* For 10GBASE-T on this hardware, skip external PHY */
if (phy_data->port_mode == XGBE_PORT_MODE_10GBASE_T) {
    netdev_info(pdata->netdev, "10GBASE-T mode - skipping external PHY\n");
    return 0;
}
```

### 3. Mode Selection Fix (xgbe-phy-v2.c)

Change 10GBASE-T to use SFI mode instead of KR mode:

```c
// Around line 2653, in xgbe_phy_switch_bp_mode()
case XGBE_MODE_KX_1000:
    return XGBE_MODE_SFI; // Changed from KR for 10GBASE-T
```

## Installation Steps

1. **Download the original driver source**:
   ```bash
   wget https://github.com/mihnea-net/amd-xgbe-asustor/archive/refs/tags/0.6.1.tar.gz
   tar -xzf 0.6.1.tar.gz
   cd amd-xgbe-asustor-0.6.1
   ```

2. **Apply the patches above** to:
   - `xgbe-ethtool.c` (kernel 6.8 compatibility)
   - `xgbe-phy-v2.c` (PHY bypass and mode selection)

3. **Compile and install**:
   ```bash
   make clean
   make
   sudo make install
   ```

4. **Load the module**:
   ```bash
   sudo modprobe -r amd_xgbe
   sudo modprobe amd_xgbe
   ```

## Network Configuration

After successful driver installation, configure the interface:

1. **Disable auto-negotiation and force 10Gbps**:
   ```bash
   ethtool -s enp228s0f2 autoneg off speed 10000 duplex full
   ```

2. **Example Proxmox network configuration** (`/etc/network/interfaces`):
   ```bash
   # 10GbE interface  
   auto enp228s0f2
   iface enp228s0f2 inet manual
       post-up ethtool -s enp228s0f2 autoneg off speed 10000 duplex full || true

   # 10GbE Bridge for containers/VMs
   auto vmbr1
   iface vmbr1 inet static
       address 192.168.0.15/24
       bridge-ports enp228s0f2
       bridge-stp off
       bridge-fd 0
   ```

## Troubleshooting

### Common Issues

1. **"get_phy_device failed" errors**: Fixed by PHY bypass patch
2. **Link flapping**: Use forced mode instead of auto-negotiation
3. **Wrong interface name**: Interface names may change (enp229s0f2 vs enp228s0f2)

### Verification Commands

```bash
# Check driver loaded
lsmod | grep amd_xgbe

# Check interface status
ip link show
ethtool enp228s0f2

# Check link negotiation
dmesg | grep xgbe

# Test performance
iperf3 -c <target_ip> -t 30
```

## Performance Results

With these patches applied:
- **Link**: 10Gbps Full Duplex
- **Mode**: SFI (not KR)
- **Stability**: No more link flapping when using forced mode

## Credits

- Original driver: [mihnea-net/amd-xgbe-asustor](https://github.com/mihnea-net/amd-xgbe-asustor)
- Hardware guide: [mihnea.net ASUSTOR FlashStor guide](https://mihnea.net/asustor-flashstor-gen-2-fs6812xfs6806x-debian-support-for-amd-xgmac-10-gbe-nics/)
- Patches developed for Proxmox VE 8.4 compatibility

## Notes

- These patches are specific to Proxmox VE 8.4 with kernel 6.8
- Auto-negotiation doesn't work reliably; use forced 10Gbps mode
- The driver works with both direct interface configuration and Proxmox bridges
- Consider having a backup network interface (USB/onboard) for management access
